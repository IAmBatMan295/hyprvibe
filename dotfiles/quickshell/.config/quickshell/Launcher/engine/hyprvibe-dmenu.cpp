// Fast, zero-dependency POSIX C++ dmenu & drun client for single-process Quickshell LauncherHost.
// Sends a compact binary header + raw UTF-8 stdin blob over Unix socket with dmenu/launcher CLI parity.

#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

namespace {

std::string jsonEscape(const std::string& s) {
  std::string out;
  out.reserve(s.size() + 8);
  for (unsigned char c : s) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out.push_back(static_cast<char>(c));
        }
    }
  }
  return out;
}

std::string defaultSocketPath() {
  if (const char* overrideSock = std::getenv("HYPRVIBE_LAUNCHER_SOCKET")) {
    if (*overrideSock) return overrideSock;
  }
  const char* xdg = std::getenv("XDG_RUNTIME_DIR");
  std::string base = (xdg && *xdg) ? xdg : "/tmp";
  return base + "/hyprvibe-launcher.sock";
}

bool parseIntArg(const char* flag, const std::string& val, int& out) {
  char* end = nullptr;
  long parsed = std::strtol(val.c_str(), &end, 10);
  if (val.empty() || !end || *end != '\0') {
    std::cerr << "Invalid integer for " << flag << ": " << val << "\n";
    return false;
  }
  out = static_cast<int>(parsed);
  return true;
}

bool writeAll(int fd, const char* buf, size_t len) {
  size_t sent = 0;
  while (sent < len) {
    ssize_t w = ::send(fd, buf + sent, len - sent, MSG_NOSIGNAL);
    if (w > 0) {
      sent += static_cast<size_t>(w);
    } else if (w < 0 && errno == EINTR) {
      continue;
    } else {
      return false;
    }
  }
  return true;
}

void printHelp() {
  std::cout << "Usage: hyprvibe-dmenu [OPTIONS]\n"
            << "  -dmenu / --dmenu         Read newline-delimited choices from stdin\n"
            << "  --preset <name>          Preset (drun|clipboard|helpers|power|profiles|theme|compact)\n"
            << "  --toggle                 Close launcher instead if already open on same preset\n"
            << "  --print-only             Print selected item even in drun mode without executing\n"
            << "  -p / --prompt <text>     Prompt label\n"
            << "  --placeholder <text>     Input placeholder text\n"
            << "  -select / --select <s>   Preselect matching entry\n"
            << "  --select-row <idx>       Preselect 0-based row index\n"
            << "  -filter / --query <q>    Initial search query\n"
            << "  --matching <mode>        fuzzy | prefix | exact | substring\n"
            << "  -i / --insensitive       Case-insensitive search (default)\n"
            << "  --case-sensitive / +i    Case-sensitive search\n"
            << "  --no-sort / --sort       Preserve input order vs score order\n"
            << "  --only-match             Disallow free-text custom submission\n"
            << "  -format / --format <f>   Output format: s (action), l (label), i (0-idx), d (1-idx), n (vis-idx), q (query)\n"
            << "  --anchor <pos>           center|top|bottom|left|right|top-left|top-right|bottom-left|bottom-right\n"
            << "  --x-offset / --y-offset  Pixel offset from anchor\n"
            << "  --margin <px>            Edge margin in pixels\n"
            << "  --width / --lines (-l)   Override card width / visible lines\n"
            << "  --search / --no-search   Toggle search bar\n"
            << "  --numbers / --no-numbers Toggle row numbers\n"
            << "  --icons / --no-icons     Toggle icons\n"
            << "  --footer / --no-footer   Toggle footer stats strip\n"
            << "  -markup-rows             Strip Pango spans cleanly\n"
            << "  --socket <path>          Unix socket override\n";
}

} // namespace

int main(int argc, char** argv) {
  std::string sockPath = defaultSocketPath();
  std::string preset = "compact";
  std::string prompt;
  std::string placeholder;
  std::string selectVal;
  std::string align;
  std::string anchor;
  std::string matching;
  std::string formatSpec;
  std::string queryVal;
  int selectRow = -1;
  int xOffset = 0;
  int yOffset = 0;
  int edgeMargin = -1;
  bool hasXOffset = false;
  bool hasYOffset = false;
  int width = -1;
  int lines = -1;
  int showSearch = -1;
  int showNumbers = -1;
  int showIcons = -1;
  int showFooter = -1;
  int sortMode = -1;
  int caseSensitive = -1;
  int onlyMatch = -1;
  bool markupRows = false;
  bool dmenuMode = false;
  bool toggleMode = false;
  bool printOnly = false;
  bool benchAutoAck = false;

  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    auto nextVal = [&](const char* flag) -> std::string {
      if (i + 1 >= argc) {
        std::cerr << "Missing value for " << flag << "\n";
        std::exit(2);
      }
      return argv[++i];
    };
    if (arg == "-h" || arg == "--help") { printHelp(); return 0; }
    else if (arg == "-dmenu" || arg == "--dmenu") dmenuMode = true;
    else if (arg == "--toggle") toggleMode = true;
    else if (arg == "--print-only") printOnly = true;
    else if (arg == "--socket") sockPath = nextVal("--socket");
    else if (arg == "--preset") preset = nextVal("--preset");
    else if (arg == "-p" || arg == "--prompt") prompt = nextVal("-p");
    else if (arg == "--placeholder") placeholder = nextVal("--placeholder");
    else if (arg == "-select" || arg == "--select") selectVal = nextVal("-select");
    else if (arg == "--select-row") {
      if (!parseIntArg("--select-row", nextVal("--select-row"), selectRow)) return 2;
    }
    else if (arg == "--align") align = nextVal("--align");
    else if (arg == "--anchor" || arg == "--location") anchor = nextVal(arg.c_str());
    else if (arg == "--x-offset") {
      if (!parseIntArg("--x-offset", nextVal("--x-offset"), xOffset)) return 2;
      hasXOffset = true;
    }
    else if (arg == "--y-offset") {
      if (!parseIntArg("--y-offset", nextVal("--y-offset"), yOffset)) return 2;
      hasYOffset = true;
    }
    else if (arg == "--margin") {
      if (!parseIntArg("--margin", nextVal("--margin"), edgeMargin)) return 2;
    }
    else if (arg == "--width") {
      if (!parseIntArg("--width", nextVal("--width"), width)) return 2;
    }
    else if (arg == "--lines" || arg == "-l") {
      if (!parseIntArg(arg.c_str(), nextVal(arg.c_str()), lines)) return 2;
    }
    else if (arg == "--matching" || arg == "-matching") {
      matching = nextVal(arg.c_str());
      if (matching != "fuzzy" && matching != "prefix" && matching != "exact" &&
          matching != "substring" && matching != "normal") {
        std::cerr << "Invalid --matching mode: " << matching << "\n";
        return 2;
      }
    }
    else if (arg == "--format" || arg == "-format") formatSpec = nextVal(arg.c_str());
    else if (arg == "--only-match" || arg == "-only-match") onlyMatch = 1;
    else if (arg == "--no-sort" || arg == "-no-sort") sortMode = 0;
    else if (arg == "--sort") sortMode = 1;
    else if (arg == "--no-search") showSearch = 0;
    else if (arg == "--search") showSearch = 1;
    else if (arg == "--numbers") showNumbers = 1;
    else if (arg == "--no-numbers") showNumbers = 0;
    else if (arg == "--icons") showIcons = 1;
    else if (arg == "--no-icons") showIcons = 0;
    else if (arg == "--footer") showFooter = 1;
    else if (arg == "--no-footer") showFooter = 0;
    else if (arg == "--query" || arg == "-filter" || arg == "--filter") queryVal = nextVal(arg.c_str());
    else if (arg == "--bench-auto-ack") benchAutoAck = true;
    else if (arg == "-markup-rows" || arg == "--markup-rows") markupRows = true;
    else if (arg == "-i" || arg == "--insensitive") caseSensitive = 0;
    else if (arg == "+i" || arg == "--case-sensitive") caseSensitive = 1;
    else {
      std::cerr << "Unknown option: " << arg << "\n";
      return 2;
    }
  }

  std::string rawBlob;
  if (dmenuMode || !::isatty(STDIN_FILENO)) {
    char chunk[65536];
    while (true) {
      ssize_t r = ::read(STDIN_FILENO, chunk, sizeof(chunk));
      if (r > 0) {
        rawBlob.append(chunk, static_cast<size_t>(r));
      } else if (r == 0) {
        break;
      } else if (errno != EINTR) {
        std::cerr << "Failed reading stdin: " << std::strerror(errno) << "\n";
        return 2;
      }
    }
  }

  std::string meta = "{";
  meta += "\"preset\":\"" + jsonEscape(preset) + "\"";
  meta += ",\"dmenu\":" + std::string(dmenuMode ? "true" : "false");
  if (toggleMode) meta += ",\"toggle\":true";
  if (printOnly) meta += ",\"printOnly\":true";
  if (!matching.empty()) meta += ",\"matching\":\"" + jsonEscape(matching) + "\"";
  if (!prompt.empty()) meta += ",\"prompt\":\"" + jsonEscape(prompt) + "\"";
  if (!placeholder.empty()) meta += ",\"placeholder\":\"" + jsonEscape(placeholder) + "\"";
  if (!selectVal.empty()) meta += ",\"select\":\"" + jsonEscape(selectVal) + "\"";
  if (selectRow >= 0) meta += ",\"selectRow\":" + std::to_string(selectRow);
  if (!align.empty()) meta += ",\"align\":\"" + jsonEscape(align) + "\"";
  if (!anchor.empty()) meta += ",\"anchor\":\"" + jsonEscape(anchor) + "\"";
  if (!formatSpec.empty()) meta += ",\"format\":\"" + jsonEscape(formatSpec) + "\"";
  if (hasXOffset) meta += ",\"xOffset\":" + std::to_string(xOffset);
  if (hasYOffset) meta += ",\"yOffset\":" + std::to_string(yOffset);
  if (edgeMargin >= 0) meta += ",\"margin\":" + std::to_string(edgeMargin);
  if (width > 0) meta += ",\"width\":" + std::to_string(width);
  if (lines > 0) meta += ",\"lines\":" + std::to_string(lines);
  if (showSearch >= 0) meta += ",\"showSearch\":" + std::string(showSearch ? "true" : "false");
  if (showNumbers >= 0) meta += ",\"showNumbers\":" + std::string(showNumbers ? "true" : "false");
  if (showIcons >= 0) meta += ",\"showIcons\":" + std::string(showIcons ? "true" : "false");
  if (showFooter >= 0) meta += ",\"showFooter\":" + std::string(showFooter ? "true" : "false");
  if (sortMode >= 0) meta += ",\"sort\":" + std::string(sortMode ? "true" : "false");
  if (caseSensitive >= 0) meta += ",\"caseSensitive\":" + std::string(caseSensitive ? "true" : "false");
  if (onlyMatch >= 0) meta += ",\"onlyMatch\":true";
  if (markupRows) meta += ",\"markupRows\":true";
  if (!queryVal.empty()) meta += ",\"query\":\"" + jsonEscape(queryVal) + "\"";
  if (benchAutoAck) meta += ",\"benchAutoAck\":true";
  meta += "}";

  uint32_t lens[2] = {
    static_cast<uint32_t>(meta.size()),
    static_cast<uint32_t>(rawBlob.size()),
  };

  int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    std::cerr << "socket failed: " << std::strerror(errno) << "\n";
    return 2;
  }

  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  if (sockPath.size() >= sizeof(addr.sun_path)) {
    std::cerr << "socket path too long\n";
    ::close(fd);
    return 2;
  }
  std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", sockPath.c_str());

  if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
    std::cerr << "connect failed (" << sockPath << "): " << std::strerror(errno) << "\n";
    ::close(fd);
    return 2;
  }

  iovec iov[3] = {
    {lens, sizeof(lens)},
    {const_cast<char*>(meta.data()), meta.size()},
    {const_cast<char*>(rawBlob.data()), rawBlob.size()},
  };
  const int iovCnt = rawBlob.empty() ? 2 : 3;
  ssize_t vw = ::writev(fd, iov, iovCnt);
  size_t totalToSend = sizeof(lens) + meta.size() + rawBlob.size();
  if (vw < 0) {
    std::cerr << "write failed: " << std::strerror(errno) << "\n";
    ::close(fd);
    return 2;
  }
  size_t sent = static_cast<size_t>(vw);
  if (sent < totalToSend) {
    size_t p1 = sizeof(lens);
    size_t p2 = p1 + meta.size();
    if (sent < p1) {
      if (!writeAll(fd, reinterpret_cast<const char*>(lens) + sent, p1 - sent)) { ::close(fd); return 2; }
      sent = p1;
    }
    if (sent < p2) {
      size_t off = sent - p1;
      if (!writeAll(fd, meta.data() + off, meta.size() - off)) { ::close(fd); return 2; }
      sent = p2;
    }
    if (sent < totalToSend) {
      size_t off = sent - p2;
      if (!writeAll(fd, rawBlob.data() + off, rawBlob.size() - off)) { ::close(fd); return 2; }
    }
  }

  std::string reply;
  char buf[4096];
  while (true) {
    ssize_t r = ::read(fd, buf, sizeof(buf));
    if (r > 0) {
      reply.append(buf, static_cast<size_t>(r));
    } else if (r == 0) {
      break;
    } else if (errno != EINTR) {
      ::close(fd);
      return 2;
    }
  }
  ::close(fd);

  if (reply == "CLEAR\n" || reply == "CLEAR") {
    return 10;
  }
  if (reply.rfind("ERR\t", 0) == 0) {
    std::cerr << "Daemon error: " << reply.substr(4);
    return 2;
  }
  if (reply.rfind("OK\t", 0) == 0) {
    std::string chosen = reply.substr(3);
    while (!chosen.empty() && (chosen.back() == '\n' || chosen.back() == '\r')) chosen.pop_back();
    std::cout << chosen << "\n";
    return 0;
  }
  return 1;
}
