#include "LauncherModel.hpp"

#include <QElapsedTimer>
#include <QFile>
#include <QFileSystemWatcher>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QPixmapCache>
#include <QSocketNotifier>
#include <algorithm>
#include <cstring>
#include <errno.h>
#include <malloc.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

namespace {

inline unsigned char normChar(unsigned char c, bool caseSens) {
  if (!caseSens && c >= 'A' && c <= 'Z') return static_cast<unsigned char>(c + 32);
  return c;
}

inline bool isBoundaryByte(char ch) {
  return ch == ' ' || ch == '-' || ch == '_' || ch == '/' || ch == '.';
}

inline int findSpan(const char* hay, int hlen, const char* needle, int nlen,
                    int startPos, bool caseSens) {
  if (nlen <= 0) return startPos;
  if (startPos + nlen > hlen) return -1;
  const unsigned char first = normChar(static_cast<unsigned char>(needle[0]), caseSens);
  const int limit = hlen - nlen;
  for (int i = startPos; i <= limit; ++i) {
    if (normChar(static_cast<unsigned char>(hay[i]), caseSens) != first) continue;
    int j = 1;
    while (j < nlen &&
           normChar(static_cast<unsigned char>(hay[i + j]), caseSens) ==
               normChar(static_cast<unsigned char>(needle[j]), caseSens)) {
      ++j;
    }
    if (j == nlen) return i;
  }
  return -1;
}

inline bool equalSpan(const char* a, int alen, const char* b, int blen, bool caseSens) {
  if (alen != blen) return false;
  if (caseSens) return std::memcmp(a, b, static_cast<size_t>(alen)) == 0;
  for (int i = 0; i < alen; ++i) {
    if (normChar(static_cast<unsigned char>(a[i]), false) !=
        normChar(static_cast<unsigned char>(b[i]), false)) {
      return false;
    }
  }
  return true;
}

inline bool startsWithSpan(const char* a, int alen, const char* b, int blen, bool caseSens) {
  if (alen < blen) return false;
  if (caseSens) return std::memcmp(a, b, static_cast<size_t>(blen)) == 0;
  for (int i = 0; i < blen; ++i) {
    if (normChar(static_cast<unsigned char>(a[i]), false) !=
        normChar(static_cast<unsigned char>(b[i]), false)) {
      return false;
    }
  }
  return true;
}

inline uint32_t leadingNumberSkip(const char* s, uint32_t len) {
  uint32_t i = 0;
  while (i < len && (s[i] == ' ' || s[i] == '\t')) ++i;
  uint32_t digitsStart = i;
  while (i < len && s[i] >= '0' && s[i] <= '9') ++i;
  if (i == digitsStart || i >= len || s[i] != '.') return 0;
  ++i;
  uint32_t wsStart = i;
  while (i < len && (s[i] == ' ' || s[i] == '\t')) ++i;
  return (i > wsStart) ? i : 0;
}

} // namespace

LauncherModel::LauncherModel(QObject* parent) : QAbstractListModel(parent) {}

LauncherModel::~LauncherModel() {
  closeClientSocket(false);
  if (m_acceptNotifier) {
    delete m_acceptNotifier;
    m_acceptNotifier = nullptr;
  }
  if (m_serverFd >= 0) {
    ::close(m_serverFd);
    m_serverFd = -1;
  }
  unlinkOwnedSocket();
}

LauncherModel::MatchMode LauncherModel::parseMatchMode(const QString& mode) {
  const QString low = mode.trimmed().toLower();
  if (low == QLatin1String("prefix")) return MatchMode::Prefix;
  if (low == QLatin1String("exact")) return MatchMode::Exact;
  if (low == QLatin1String("substring") || low == QLatin1String("normal")) return MatchMode::Substring;
  return MatchMode::Fuzzy;
}

QString LauncherModel::matchingMode() const {
  switch (m_matchMode) {
    case MatchMode::Prefix: return QStringLiteral("prefix");
    case MatchMode::Exact: return QStringLiteral("exact");
    case MatchMode::Substring: return QStringLiteral("substring");
    case MatchMode::Fuzzy:
    default: return QStringLiteral("fuzzy");
  }
}

void LauncherModel::setMatchingMode(const QString& mode) {
  MatchMode parsed = parseMatchMode(mode);
  if (m_matchMode == parsed) return;
  m_matchMode = parsed;
  emit matchingModeChanged();
  refilter();
}

void LauncherModel::setCaseSensitive(bool cs) {
  if (m_caseSensitive == cs) return;
  m_caseSensitive = cs;
  emit caseSensitiveChanged();
  refilter();
}

void LauncherModel::setSortEnabled(bool enabled) {
  if (m_sortEnabled == enabled) return;
  m_sortEnabled = enabled;
  emit sortEnabledChanged();
  refilter();
}

void LauncherModel::applyMatchOptions(const QString& mode, bool cs, bool sortEn) {
  MatchMode parsed = parseMatchMode(mode);
  if (m_matchMode != parsed) {
    m_matchMode = parsed;
    emit matchingModeChanged();
  }
  if (m_caseSensitive != cs) {
    m_caseSensitive = cs;
    emit caseSensitiveChanged();
  }
  if (m_sortEnabled != sortEn) {
    m_sortEnabled = sortEn;
    emit sortEnabledChanged();
  }
}

LauncherModel::Span LauncherModel::appendBlob(const char* ptr, uint32_t len) {
  if (len == 0) return {0, 0};
  const uint32_t off = static_cast<uint32_t>(m_blob.size());
  m_blob.append(ptr, static_cast<qsizetype>(len));
  return {off, len};
}

LauncherModel::Span LauncherModel::appendUtf8(const QByteArray& bytes) {
  return appendBlob(bytes.constData(), static_cast<uint32_t>(bytes.size()));
}

QString LauncherModel::decodeSpan(uint32_t off, uint32_t len) const {
  if (len == 0) return {};
  return QString::fromUtf8(m_blob.constData() + off, static_cast<qsizetype>(len));
}

QByteArray LauncherModel::stripPangoUtf8(const char* s, int len) {
  QByteArray out;
  out.reserve(len);
  bool inTag = false;
  for (int i = 0; i < len; ++i) {
    char c = s[i];
    if (c == '<') { inTag = true; continue; }
    if (inTag) { if (c == '>') inTag = false; continue; }
    if (c == '&') {
      if (i + 4 < len && std::memcmp(s + i, "&amp;", 5) == 0) { out.append('&'); i += 4; continue; }
      if (i + 3 < len && std::memcmp(s + i, "&lt;", 4) == 0) { out.append('<'); i += 3; continue; }
      if (i + 3 < len && std::memcmp(s + i, "&gt;", 4) == 0) { out.append('>'); i += 3; continue; }
    }
    out.append(c);
  }
  return out;
}

int LauncherModel::rowCount(const QModelIndex& parent) const {
  if (parent.isValid()) return 0;
  return static_cast<int>(m_filtered.size());
}

QVariant LauncherModel::data(const QModelIndex& index, int role) const {
  if (!index.isValid()) return {};
  const int row = index.row();
  if (row < 0 || row >= static_cast<int>(m_filtered.size())) return {};

  const ScoredRow& sr = m_filtered[row];
  const Entry& e = m_entries[sr.idx];
  switch (role) {
    case LabelRole: return decodeSpan(e.labelOff, e.labelLen);
    case SubtextRole: return decodeSpan(e.subOff, e.subLen);
    case IconRole: return decodeSpan(e.iconOff, e.iconLen);
    case ActionRole: return decodeSpan(e.actionOff, e.actionLen);
    case ActiveRole: return e.isActive;
    case RowNumberRole: return row + 1;
    case OriginalIndexRole: return e.baseOrder;
    case ScoreRole: return sr.score;
    default: return {};
  }
}

QHash<int, QByteArray> LauncherModel::roleNames() const {
  return {
    {LabelRole, "label"},
    {SubtextRole, "subtext"},
    {IconRole, "icon"},
    {ActionRole, "actionValue"},
    {ActiveRole, "isActive"},
    {RowNumberRole, "rowNumber"},
    {OriginalIndexRole, "originalIndex"},
    {ScoreRole, "score"},
  };
}

void LauncherModel::setQuery(const QString& query) {
  if (m_query == query) return;
  m_query = query;
  emit queryChanged();
  refilter();
}

void LauncherModel::loadItems(const QVariantList& items) {
  m_entries.clear();
  m_blob.clear();
  m_entries.reserve(items.size());
  m_blob.reserve(items.size() * 72);

  int order = 0;
  for (const QVariant& v : items) {
    const QVariantMap m = v.toMap();
    const QByteArray labelB = m.value(QStringLiteral("label")).toString().toUtf8();
    const QByteArray subB = m.value(QStringLiteral("subtext")).toString().toUtf8();
    const QByteArray iconB = m.value(QStringLiteral("icon")).toString().toUtf8();
    const QVariant actVar = m.value(QStringLiteral("actionValue"));
    const QByteArray actionB = actVar.isValid() ? actVar.toString().toUtf8() : labelB;
    const QByteArray kwB = m.value(QStringLiteral("keywords")).toString().toUtf8();

    Entry e;
    Span ls = appendUtf8(labelB);
    Span ss = appendUtf8(subB);
    Span is = appendUtf8(iconB);
    Span as = (actVar.isValid() && actionB != labelB) ? appendUtf8(actionB) : ls;

    e.labelOff = ls.off; e.labelLen = ls.len;
    e.subOff = ss.off; e.subLen = ss.len;
    e.iconOff = is.off; e.iconLen = is.len;
    e.actionOff = as.off; e.actionLen = as.len;
    e.isActive = m.value(QStringLiteral("isActive"), false).toBool();
    e.baseOrder = order++;

    if (subB.isEmpty() && kwB.isEmpty()) {
      e.hayOff = e.labelOff;
      e.hayLen = e.labelLen;
    } else {
      QByteArray hay = labelB;
      if (!subB.isEmpty()) { hay.append(' '); hay.append(subB); }
      if (!kwB.isEmpty()) { hay.append(' '); hay.append(kwB); }
      Span hs = appendUtf8(hay);
      e.hayOff = hs.off;
      e.hayLen = hs.len;
    }
    m_entries.push_back(e);
  }

  emit totalCountChanged();
  refilter();
}

int LauncherModel::loadLines(const QStringList& lines, bool stripMarkup,
                             bool parseNumbers, const QString& activeMatch) {
  m_entries.clear();
  m_blob.clear();
  m_blob.reserve(lines.size() * 48);

  for (const QString& s : lines) {
    if (s.isEmpty()) continue;
    m_blob.append(s.toUtf8());
    m_blob.append('\n');
  }
  const uint32_t rawEnd = static_cast<uint32_t>(m_blob.size());
  int activeRow = -1;
  parseRawBlobEntries(rawEnd, stripMarkup, parseNumbers, activeMatch.toUtf8(), activeRow);

  emit totalCountChanged();
  refilter();
  return activeRow;
}

void LauncherModel::parseRawBlobEntries(uint32_t blobEnd, bool stripMarkup, bool parseNumbers,
                                        const QByteArray& activeMatchUtf8, int& activeRow) {
  m_entries.clear();
  m_entries.reserve(std::max<size_t>(16, blobEnd / 32));
  activeRow = -1;
  int order = 0;

  uint32_t pos = 0;
  while (pos < blobEnd) {
    const char* rawBase = m_blob.constData();
    const void* nl = std::memchr(rawBase + pos, '\n', blobEnd - pos);
    uint32_t lineEnd = nl ? static_cast<uint32_t>(static_cast<const char*>(nl) - rawBase) : blobEnd;
    uint32_t lineLen = lineEnd - pos;
    if (lineLen > 0 && rawBase[pos + lineLen - 1] == '\r') --lineLen;
    const uint32_t lineOff = pos;
    pos = lineEnd + 1;

    if (lineLen == 0) continue;

    Entry e;
    uint32_t cleanOff = lineOff;
    uint32_t cleanLen = lineLen;
    bool rawHasColor = false;

    if (stripMarkup && std::memchr(rawBase + lineOff, '<', lineLen) != nullptr) {
      rawHasColor = (findSpan(rawBase + lineOff, static_cast<int>(lineLen), "color=", 6, 0, false) >= 0);
      QByteArray stripped = stripPangoUtf8(rawBase + lineOff, static_cast<int>(lineLen));
      if (stripped.isEmpty()) continue;
      Span cs = appendUtf8(stripped);
      cleanOff = cs.off;
      cleanLen = cs.len;
    }

    const char* data = m_blob.constData();
    e.actionOff = cleanOff;
    e.actionLen = cleanLen;

    const void* t1 = std::memchr(data + cleanOff, '\t', cleanLen);
    if (t1 != nullptr) {
      const uint32_t p1 = static_cast<uint32_t>(static_cast<const char*>(t1) - (data + cleanOff));
      e.iconOff = cleanOff;
      e.iconLen = p1;
      const uint32_t remStart = cleanOff + p1 + 1;
      const uint32_t remLen = cleanLen - p1 - 1;
      const void* t2 = std::memchr(data + remStart, '\t', remLen);
      if (t2 != nullptr) {
        const uint32_t p2 = static_cast<uint32_t>(static_cast<const char*>(t2) - (data + remStart));
        e.labelOff = remStart;
        e.labelLen = p2;
        e.subOff = remStart + p2 + 1;
        e.subLen = remLen - p2 - 1;
      } else {
        e.labelOff = remStart;
        e.labelLen = remLen;
      }
    } else if (parseNumbers) {
      const uint32_t skip = leadingNumberSkip(data + cleanOff, cleanLen);
      e.labelOff = cleanOff + skip;
      e.labelLen = cleanLen - skip;
    } else {
      e.labelOff = cleanOff;
      e.labelLen = cleanLen;
    }

    if (e.subLen == 0) {
      e.hayOff = e.labelOff;
      e.hayLen = e.labelLen;
    } else {
      QByteArray hay;
      hay.reserve(static_cast<qsizetype>(e.labelLen + 1 + e.subLen));
      hay.append(data + e.labelOff, static_cast<qsizetype>(e.labelLen));
      hay.append(' ');
      hay.append(data + e.subOff, static_cast<qsizetype>(e.subLen));
      Span hs = appendUtf8(hay);
      e.hayOff = hs.off;
      e.hayLen = hs.len;
      data = m_blob.constData();
    }

    if (!activeMatchUtf8.isEmpty()) {
      const int amLen = activeMatchUtf8.size();
      const char* amPtr = activeMatchUtf8.constData();
      const bool labelMatch = (static_cast<int>(e.labelLen) == amLen &&
                               std::memcmp(data + e.labelOff, amPtr, amLen) == 0);
      const bool actMatch = (static_cast<int>(e.actionLen) == amLen &&
                             std::memcmp(data + e.actionOff, amPtr, amLen) == 0);
      if (labelMatch || actMatch || (rawHasColor && actMatch)) {
        e.isActive = true;
        activeRow = order;
      }
    }

    e.baseOrder = order++;
    m_entries.push_back(e);
  }
}

void LauncherModel::clear() {
  if (!m_entries.empty() || !m_filtered.empty() || !m_blob.isEmpty()) {
    beginResetModel();
    std::vector<Entry>().swap(m_entries);
    std::vector<ScoredRow>().swap(m_filtered);
    QByteArray().swap(m_blob);
    endResetModel();
    if (!m_query.isEmpty()) {
      m_query.clear();
      emit queryChanged();
    }
    emit countChanged();
    emit totalCountChanged();
  }
  QPixmapCache::clear();
  ::malloc_trim(0);
}

QString LauncherModel::actionAt(int row) const {
  if (row < 0 || row >= static_cast<int>(m_filtered.size())) return {};
  const Entry& e = m_entries[m_filtered[row].idx];
  return decodeSpan(e.actionOff, e.actionLen);
}

QString LauncherModel::labelAt(int row) const {
  if (row < 0 || row >= static_cast<int>(m_filtered.size())) return {};
  const Entry& e = m_entries[m_filtered[row].idx];
  return decodeSpan(e.labelOff, e.labelLen);
}

QString LauncherModel::formatSelection(int row, const QString& formatSpec) const {
  if (row < 0 || row >= static_cast<int>(m_filtered.size())) return {};
  const Entry& e = m_entries[m_filtered[row].idx];
  const QString spec = formatSpec.isEmpty() ? QStringLiteral("s") : formatSpec;
  if (spec == QLatin1String("l")) return decodeSpan(e.labelOff, e.labelLen);
  if (spec == QLatin1String("i")) return QString::number(e.baseOrder);
  if (spec == QLatin1String("d")) return QString::number(e.baseOrder + 1);
  if (spec == QLatin1String("n")) return QString::number(row);
  if (spec == QLatin1String("q")) return m_query;
  return decodeSpan(e.actionOff, e.actionLen);
}

QVariantMap LauncherModel::rowAt(int row) const {
  QVariantMap map;
  if (row < 0 || row >= static_cast<int>(m_filtered.size())) return map;
  const Entry& e = m_entries[m_filtered[row].idx];
  map[QStringLiteral("label")] = decodeSpan(e.labelOff, e.labelLen);
  map[QStringLiteral("subtext")] = decodeSpan(e.subOff, e.subLen);
  map[QStringLiteral("icon")] = decodeSpan(e.iconOff, e.iconLen);
  map[QStringLiteral("actionValue")] = decodeSpan(e.actionOff, e.actionLen);
  map[QStringLiteral("isActive")] = e.isActive;
  map[QStringLiteral("rowNumber")] = row + 1;
  map[QStringLiteral("originalIndex")] = e.baseOrder;
  return map;
}

void LauncherModel::recordLaunch(const QString& key) {
  if (!key.isEmpty()) m_frecency[key] += 1;
}

int LauncherModel::scoreSingleTerm(const char* hay, int hlen,
                                   const char* label, int llen,
                                   const char* term, int tlen,
                                   MatchMode mode, bool caseSens) {
  if (tlen <= 0) return 1;

  if (equalSpan(label, llen, term, tlen, caseSens)) return 100000;
  if (mode == MatchMode::Exact) {
    return (hay != label && equalSpan(hay, hlen, term, tlen, caseSens)) ? 90000 : -1;
  }

  if (startsWithSpan(label, llen, term, tlen, caseSens)) return 50000 - llen;
  if (mode == MatchMode::Prefix) {
    return (hay != label && startsWithSpan(hay, hlen, term, tlen, caseSens)) ? (45000 - hlen) : -1;
  }

  const int lpos = findSpan(label, llen, term, tlen, 1, caseSens);
  if (lpos > 0) {
    if (isBoundaryByte(label[lpos - 1])) return 32000 - lpos * 4;
    return 18000 - lpos * 4;
  }

  if (hay != label || hlen != llen) {
    const int hpos = findSpan(hay, hlen, term, tlen, 0, caseSens);
    if (hpos >= 0) {
      if (hpos == 0 || isBoundaryByte(hay[hpos - 1])) return 12000 - hpos * 2;
      return 8000 - hpos;
    }
  }

  if (mode == MatchMode::Substring) return -1;

  int ti = 0;
  int score = 1000;
  int consec = 0;
  unsigned char target = normChar(static_cast<unsigned char>(term[0]), caseSens);
  for (int hi = 0; hi < hlen && ti < tlen; ++hi) {
    if (normChar(static_cast<unsigned char>(hay[hi]), caseSens) == target) {
      consec += 1;
      score += 40 + consec * 25;
      if (hi == 0 || isBoundaryByte(hay[hi - 1])) score += 80;
      ti += 1;
      if (ti < tlen) target = normChar(static_cast<unsigned char>(term[ti]), caseSens);
    } else {
      consec = 0;
      score -= 2;
    }
  }
  return (ti == tlen) ? std::max(100, score) : -1;
}

int LauncherModel::scoreTerms(const char* blob, const Entry& e,
                              const std::vector<QByteArray>& terms,
                              int freqBoost, MatchMode mode, bool caseSens) {
  const char* hay = blob + e.hayOff;
  const int hlen = static_cast<int>(e.hayLen);
  const char* label = blob + e.labelOff;
  const int llen = static_cast<int>(e.labelLen);

  int sum = 0;
  for (const QByteArray& term : terms) {
    const int s = scoreSingleTerm(hay, hlen, label, llen,
                                  term.constData(), static_cast<int>(term.size()),
                                  mode, caseSens);
    if (s < 0) return -1;
    sum += s;
  }
  return sum + freqBoost * 150;
}

void LauncherModel::refilter() {
  QElapsedTimer timer;
  timer.start();

  const QString trimmed = m_query.trimmed();
  std::vector<QByteArray> terms;
  if (!trimmed.isEmpty()) {
    const QByteArray rawQ = m_caseSensitive ? trimmed.toUtf8() : trimmed.toLower().toUtf8();
    const QList<QByteArray> parts = rawQ.split(' ');
    for (const QByteArray& p : parts) {
      if (!p.isEmpty()) terms.push_back(p);
    }
  }

  std::vector<ScoredRow> next;
  const int n = static_cast<int>(m_entries.size());
  next.reserve(n);

  const bool hasFrecency = !m_frecency.isEmpty();
  const char* blob = m_blob.constData();

  if (terms.empty()) {
    if (!hasFrecency || !m_sortEnabled) {
      for (int i = 0; i < n; ++i) next.push_back({i, -i});
    } else {
      for (int i = 0; i < n; ++i) {
        const Entry& e = m_entries[i];
        const int boost = m_frecency.value(decodeSpan(e.actionOff, e.actionLen), 0);
        next.push_back({i, boost * 150 - e.baseOrder});
      }
      std::stable_sort(next.begin(), next.end(), [](const ScoredRow& a, const ScoredRow& b) {
        return a.score > b.score;
      });
    }
  } else {
    for (int i = 0; i < n; ++i) {
      const Entry& e = m_entries[i];
      const int boost = hasFrecency
                            ? m_frecency.value(decodeSpan(e.actionOff, e.actionLen), 0)
                            : 0;
      const int s = scoreTerms(blob, e, terms, boost, m_matchMode, m_caseSensitive);
      if (s >= 0) next.push_back({i, s});
    }
    if (m_sortEnabled) {
      std::stable_sort(next.begin(), next.end(), [this](const ScoredRow& a, const ScoredRow& b) {
        if (a.score != b.score) return a.score > b.score;
        return m_entries[a.idx].baseOrder < m_entries[b.idx].baseOrder;
      });
    }
  }

  const int prevCount = static_cast<int>(m_filtered.size());
  beginResetModel();
  m_filtered = std::move(next);
  endResetModel();

  m_lastFilterUs = timer.nsecsElapsed() / 1000;
  emit lastFilterUsChanged();
  if (prevCount != static_cast<int>(m_filtered.size())) emit countChanged();
}

void LauncherModel::unlinkOwnedSocket() {
  if (m_socketPath.isEmpty() || m_serverIno == 0) return;
  const QByteArray pathUtf8 = m_socketPath.toUtf8();
  struct stat st{};
  if (::lstat(pathUtf8.constData(), &st) == 0 &&
      static_cast<uint64_t>(st.st_dev) == m_serverDev &&
      static_cast<uint64_t>(st.st_ino) == m_serverIno) {
    QFile::remove(m_socketPath);
  }
  m_serverDev = 0;
  m_serverIno = 0;
}

bool LauncherModel::startIpcServer(const QString& socketPath) {
  if (socketPath.isEmpty()) return false;
  if (m_serverFd >= 0) {
    delete m_acceptNotifier;
    m_acceptNotifier = nullptr;
    ::close(m_serverFd);
    m_serverFd = -1;
    unlinkOwnedSocket();
  }
  QFile::remove(socketPath);
  m_socketPath = socketPath;

  const QByteArray pathUtf8 = socketPath.toUtf8();
  sockaddr_un addr{};
  if (static_cast<size_t>(pathUtf8.size()) >= sizeof(addr.sun_path)) return false;

  int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
  if (fd < 0) return false;

  addr.sun_family = AF_UNIX;
  std::memcpy(addr.sun_path, pathUtf8.constData(), static_cast<size_t>(pathUtf8.size()) + 1);
  if (::bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0 ||
      ::listen(fd, 16) < 0) {
    ::close(fd);
    return false;
  }

  struct stat st{};
  if (::lstat(pathUtf8.constData(), &st) == 0) {
    m_serverDev = static_cast<uint64_t>(st.st_dev);
    m_serverIno = static_cast<uint64_t>(st.st_ino);
  } else {
    m_serverDev = 0;
    m_serverIno = 0;
  }

  m_serverFd = fd;
  m_acceptNotifier = new QSocketNotifier(m_serverFd, QSocketNotifier::Read, this);
  connect(m_acceptNotifier, &QSocketNotifier::activated, this, &LauncherModel::onNewConnection);
  return true;
}

void LauncherModel::closeClientSocket(bool notifyCancel, const char* customReply) {
  if (m_readNotifier) {
    m_readNotifier->setEnabled(false);
    m_readNotifier->deleteLater();
    m_readNotifier = nullptr;
  }
  if (m_clientFd >= 0) {
    if (customReply != nullptr) {
      (void)::send(m_clientFd, customReply, std::strlen(customReply), MSG_NOSIGNAL);
    } else if (notifyCancel) {
      static const char kCancel[] = "CANCEL\n";
      (void)::send(m_clientFd, kCancel, sizeof(kCancel) - 1, MSG_NOSIGNAL);
    }
    ::close(m_clientFd);
    m_clientFd = -1;
  }
  QByteArray().swap(m_rxBuf);
  m_expectedMetaLen = 0;
  m_expectedBlobLen = 0;
  m_headerParsed = false;
}

void LauncherModel::replyIpc(const QString& reply) {
  if (m_clientFd < 0) return;
  const QByteArray bytes = reply.toUtf8();
  const char* ptr = bytes.constData();
  qsizetype sent = 0;
  while (sent < bytes.size()) {
    ssize_t w = ::send(m_clientFd, ptr + sent, static_cast<size_t>(bytes.size() - sent), MSG_NOSIGNAL);
    if (w > 0) {
      sent += w;
    } else if (w < 0 && errno == EINTR) {
      continue;
    } else {
      break;
    }
  }
  closeClientSocket(false);
}

void LauncherModel::onNewConnection() {
  while (m_serverFd >= 0) {
    int cfd = ::accept4(m_serverFd, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
    if (cfd < 0) {
      if (errno == EINTR) continue;
      break;
    }
    closeClientSocket(true);
    m_clientFd = cfd;
    m_rxBuf.clear();
    m_headerParsed = false;
    m_expectedMetaLen = 0;
    m_expectedBlobLen = 0;
    m_readNotifier = new QSocketNotifier(m_clientFd, QSocketNotifier::Read, this);
    connect(m_readNotifier, &QSocketNotifier::activated, this, &LauncherModel::onClientReadable);
    onClientReadable();
  }
}

void LauncherModel::onClientReadable() {
  if (m_clientFd < 0) return;
  char buf[65536];
  while (m_clientFd >= 0) {
    ssize_t r = ::read(m_clientFd, buf, sizeof(buf));
    if (r > 0) {
      m_rxBuf.append(buf, static_cast<qsizetype>(r));
      if (!m_headerParsed && m_rxBuf.size() >= 8) {
        std::memcpy(&m_expectedMetaLen, m_rxBuf.constData(), 4);
        std::memcpy(&m_expectedBlobLen, m_rxBuf.constData() + 4, 4);
        if (m_expectedMetaLen > 65536 || m_expectedBlobLen > 64u * 1024u * 1024u) {
          m_errorCount += 1;
          emit errorCountChanged();
          emit ipcProtocolError(QStringLiteral("Oversized IPC frame rejected"));
          closeClientSocket(false, "ERR\tpayload_too_large\n");
          emit ipcClientCancelled();
          return;
        }
        m_rxBuf.reserve(static_cast<qsizetype>(8 + m_expectedMetaLen + m_expectedBlobLen));
        m_headerParsed = true;
      }
      if (m_headerParsed &&
          static_cast<uint32_t>(m_rxBuf.size()) >= 8u + m_expectedMetaLen + m_expectedBlobLen) {
        handleIncomingPacket();
        return;
      }
    } else if (r == 0) {
      if (!m_rxBuf.isEmpty()) {
        m_errorCount += 1;
        emit errorCountChanged();
        emit ipcProtocolError(QStringLiteral("Truncated IPC frame disconnected"));
      }
      closeClientSocket(false);
      emit ipcClientCancelled();
      return;
    } else {
      if (errno == EINTR) continue;
      if (errno == EAGAIN || errno == EWOULDBLOCK) break;
      m_errorCount += 1;
      emit errorCountChanged();
      closeClientSocket(false);
      emit ipcClientCancelled();
      return;
    }
  }
}

void LauncherModel::handleIncomingPacket() {
  const char* base = m_rxBuf.constData();
  const QByteArray metaBytes(base + 8, static_cast<qsizetype>(m_expectedMetaLen));
  QJsonParseError parseErr{};
  const QJsonDocument doc = QJsonDocument::fromJson(metaBytes, &parseErr);
  if (m_expectedMetaLen > 0 && parseErr.error != QJsonParseError::NoError) {
    m_errorCount += 1;
    emit errorCountChanged();
    emit ipcProtocolError(QStringLiteral("Malformed metadata JSON: ") + parseErr.errorString());
    closeClientSocket(false, "ERR\tmalformed_json\n");
    emit ipcClientCancelled();
    return;
  }

  QVariantMap meta = doc.object().toVariantMap();
  const bool stripMarkup = meta.value(QStringLiteral("markupRows"), false).toBool();
  const QByteArray activeMatchUtf8 = meta.value(QStringLiteral("select")).toString().toUtf8();
  const bool wantNums = meta.value(QStringLiteral("showNumbers"), false).toBool() ||
                        meta.value(QStringLiteral("preset")).toString() == QLatin1String("clipboard");

  const QString matchModeStr = meta.value(QStringLiteral("matching"), QStringLiteral("fuzzy")).toString();
  const bool csFlag = meta.value(QStringLiteral("caseSensitive"), false).toBool();
  const bool sortFlag = meta.value(QStringLiteral("sort"), true).toBool();
  applyMatchOptions(matchModeStr, csFlag, sortFlag);

  m_blob.clear();
  if (m_expectedBlobLen > 0) {
    m_blob.append(base + 8 + m_expectedMetaLen, static_cast<qsizetype>(m_expectedBlobLen));
  }
  QByteArray().swap(m_rxBuf);
  m_headerParsed = false;

  int activeRow = -1;
  if (m_expectedBlobLen > 0) {
    parseRawBlobEntries(m_expectedBlobLen, stripMarkup, wantNums, activeMatchUtf8, activeRow);
  } else {
    m_entries.clear();
  }

  const QString nextQuery = meta.value(QStringLiteral("query")).toString();
  if (m_query != nextQuery) {
    m_query = nextQuery;
    emit queryChanged();
  }

  emit totalCountChanged();
  refilter();

  meta[QStringLiteral("itemCount")] = static_cast<int>(m_entries.size());
  meta[QStringLiteral("activeRow")] = activeRow;
  emit ipcRequestReceived(meta);
}

qint64 LauncherModel::runSynthetic10kBenchmark(const QString& sampleQuery) {
  QStringList lines;
  lines.reserve(10000);
  for (int i = 0; i < 10000; ++i) {
    lines.append(QStringLiteral("Clipboard Item #%1 — project/module/service_%2.qml")
                     .arg(i).arg(i * 7 % 997));
  }
  loadLines(lines, false, false, {});
  setQuery(sampleQuery);
  return m_lastFilterUs;
}

void LauncherModel::watchPath(const QString& path) {
  if (path.isEmpty() || !QFile::exists(path)) return;
  if (!m_fsWatcher) {
    m_fsWatcher = new QFileSystemWatcher(this);
    connect(m_fsWatcher, &QFileSystemWatcher::fileChanged, this, [this](const QString& p) {
      if (QFile::exists(p) && !m_fsWatcher->files().contains(p)) m_fsWatcher->addPath(p);
      emit watchedPathChanged(p);
    });
    connect(m_fsWatcher, &QFileSystemWatcher::directoryChanged, this, &LauncherModel::watchedPathChanged);
  }
  m_fsWatcher->addPath(path);
}
