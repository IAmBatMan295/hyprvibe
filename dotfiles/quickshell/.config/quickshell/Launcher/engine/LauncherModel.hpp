#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <cstdint>
#include <vector>

class QFileSystemWatcher;
class QSocketNotifier;

class LauncherModel : public QAbstractListModel {
  Q_OBJECT
  Q_PROPERTY(int count READ count NOTIFY countChanged)
  Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)
  Q_PROPERTY(qint64 lastFilterUs READ lastFilterUs NOTIFY lastFilterUsChanged)
  Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
  Q_PROPERTY(QString matchingMode READ matchingMode WRITE setMatchingMode NOTIFY matchingModeChanged)
  Q_PROPERTY(bool caseSensitive READ caseSensitive WRITE setCaseSensitive NOTIFY caseSensitiveChanged)
  Q_PROPERTY(bool sortEnabled READ sortEnabled WRITE setSortEnabled NOTIFY sortEnabledChanged)
  Q_PROPERTY(QString historyPath READ historyPath WRITE setHistoryPath NOTIFY historyPathChanged)
  Q_PROPERTY(QString highlightColor READ highlightColor WRITE setHighlightColor NOTIFY highlightColorChanged)
  Q_PROPERTY(int errorCount READ errorCount NOTIFY errorCountChanged)

public:
  enum Roles {
    LabelRole = Qt::UserRole + 1,
    SubtextRole,
    IconRole,
    ActionRole,
    ActiveRole,
    RowNumberRole,
    OriginalIndexRole,
    ScoreRole,
    HighlightedLabelRole
  };

  enum class MatchMode {
    Fuzzy = 0,
    Prefix = 1,
    Exact = 2,
    Substring = 3
  };

  explicit LauncherModel(QObject* parent = nullptr);
  ~LauncherModel() override;

  int rowCount(const QModelIndex& parent = QModelIndex()) const override;
  QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
  QHash<int, QByteArray> roleNames() const override;

  int count() const { return static_cast<int>(m_filtered.size()); }
  int totalCount() const { return static_cast<int>(m_entries.size()); }
  qint64 lastFilterUs() const { return m_lastFilterUs; }
  QString query() const { return m_query; }
  void setQuery(const QString& query);

  QString matchingMode() const;
  void setMatchingMode(const QString& mode);
  bool caseSensitive() const { return m_caseSensitive; }
  void setCaseSensitive(bool cs);
  bool sortEnabled() const { return m_sortEnabled; }
  void setSortEnabled(bool enabled);
  QString historyPath() const { return m_historyPath; }
  void setHistoryPath(const QString& path);
  QString highlightColor() const { return m_highlightColor; }
  void setHighlightColor(const QString& color);
  int errorCount() const { return m_errorCount; }

  Q_INVOKABLE bool startIpcServer(const QString& socketPath);
  Q_INVOKABLE void replyIpc(const QString& reply);
  Q_INVOKABLE bool hasActiveIpc() const { return m_clientFd >= 0; }
  Q_INVOKABLE void watchPath(const QString& path);

  Q_INVOKABLE void loadItems(const QVariantList& items);
  Q_INVOKABLE int loadLines(const QStringList& lines, bool stripMarkup = true,
                            bool parseNumbers = false, const QString& activeMatch = QString());
  Q_INVOKABLE void clear();
  Q_INVOKABLE QString actionAt(int row) const;
  Q_INVOKABLE QString labelAt(int row) const;
  Q_INVOKABLE QString formatSelection(int row, const QString& formatSpec) const;
  Q_INVOKABLE QVariantMap rowAt(int row) const;
  Q_INVOKABLE void recordLaunch(const QString& key);
  Q_INVOKABLE qint64 runSynthetic10kBenchmark(const QString& sampleQuery);

signals:
  void countChanged();
  void totalCountChanged();
  void lastFilterUsChanged();
  void queryChanged();
  void matchingModeChanged();
  void caseSensitiveChanged();
  void sortEnabledChanged();
  void historyPathChanged();
  void highlightColorChanged();
  void errorCountChanged();
  void ipcRequestReceived(const QVariantMap& meta);
  void ipcClientCancelled();
  void ipcProtocolError(const QString& reason);
  void watchedPathChanged(const QString& path);

private slots:
  void onNewConnection();
  void onClientReadable();

private:
  struct Entry {
    uint32_t labelOff = 0;
    uint32_t labelLen = 0;
    uint32_t subOff = 0;
    uint32_t subLen = 0;
    uint32_t iconOff = 0;
    uint32_t iconLen = 0;
    uint32_t actionOff = 0;
    uint32_t actionLen = 0;
    uint32_t hayOff = 0;
    uint32_t hayLen = 0;
    int baseOrder = 0;
    bool isActive = false;
  };

  struct ScoredRow {
    int idx;
    int score;
    int freq = 0;
    bool labelMatch = true;
  };

  struct Span {
    uint32_t off;
    uint32_t len;
  };

  Span appendBlob(const char* ptr, uint32_t len);
  Span appendUtf8(const QByteArray& bytes);
  QString decodeSpan(uint32_t off, uint32_t len) const;

  void parseRawBlobEntries(uint32_t blobEnd, bool stripMarkup, bool parseNumbers,
                           const QByteArray& activeMatchUtf8, int& activeRow);
  void handleIncomingPacket();
  void closeClientSocket(bool notifyCancel, const char* customReply = nullptr);
  void unlinkOwnedSocket();
  void applyMatchOptions(const QString& mode, bool cs, bool sortEn);

  void refilter();
  int frecencyBoost(const QString& actionKey) const;
  void loadHistory();
  void saveHistory() const;
  static int scoreTerms(const char* blob, const Entry& e,
                        const std::vector<QByteArray>& terms,
                        MatchMode mode, bool caseSens,
                        bool& labelMatchedOut);
  static int scoreSingleTerm(const char* hay, int hlen,
                             const char* label, int llen,
                             const char* term, int tlen,
                             MatchMode mode, bool caseSens,
                             bool& matchedInLabelOut);
  static QByteArray stripPangoUtf8(const char* s, int len);
  static MatchMode parseMatchMode(const QString& mode);
  QString buildHighlightedLabel(const QString& label) const;

  QByteArray m_blob;
  std::vector<Entry> m_entries;
  std::vector<ScoredRow> m_filtered;
  QHash<QString, int> m_frecency;
  QString m_historyPath;
  QString m_highlightColor = QStringLiteral("#a63232");
  bool m_fromLoadItems = false;
  QString m_query;
  MatchMode m_matchMode = MatchMode::Fuzzy;
  bool m_caseSensitive = false;
  bool m_sortEnabled = true;
  qint64 m_lastFilterUs = 0;
  int m_errorCount = 0;

  QString m_socketPath;
  uint64_t m_serverDev = 0;
  uint64_t m_serverIno = 0;
  int m_serverFd = -1;
  int m_clientFd = -1;
  QSocketNotifier* m_acceptNotifier = nullptr;
  QSocketNotifier* m_readNotifier = nullptr;
  QFileSystemWatcher* m_fsWatcher = nullptr;
  QByteArray m_rxBuf;
  uint32_t m_expectedMetaLen = 0;
  uint32_t m_expectedBlobLen = 0;
  bool m_headerParsed = false;
};
