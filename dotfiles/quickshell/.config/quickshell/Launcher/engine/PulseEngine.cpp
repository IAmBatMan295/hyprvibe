#include "PulseEngine.hpp"

#include <QList>
#include <QMetaObject>
#include <QPair>
#include <QPointer>
#include <pulse/pulseaudio.h>

#include <cstring>
#include <memory>

namespace {

struct SinkEntry {
  uint32_t index = PA_INVALID_INDEX;
  QString name;
  bool available = true;
};

struct SinkInputEntry {
  uint32_t index = PA_INVALID_INDEX;
  uint32_t sinkIndex = PA_INVALID_INDEX;
  QString nodeName;
  QString appName;
};

struct PulseSnapshot {
  PulseEngine* owner = nullptr;
  QPointer<PulseEngine> guard;
  QString defaultSink;
  QList<SinkEntry> sinks;
  QList<SinkInputEntry> inputs;
  int pendingOps = 3;

  void maybeFinish() {
    if (--pendingOps > 0 || !guard) return;

    QVariantMap availMap;
    QString resolved = defaultSink;

    for (const SinkEntry& s : sinks) {
      if (!s.name.isEmpty()) {
        availMap.insert(s.name, s.available);
      }
    }

    if (!defaultSink.isEmpty() && !defaultSink.startsWith(QStringLiteral("alsa_output."))) {
      uint32_t downstreamIdx = PA_INVALID_INDEX;
      for (const SinkInputEntry& si : inputs) {
        if ((!si.nodeName.isEmpty() && si.nodeName.startsWith(defaultSink)) ||
            (defaultSink == QStringLiteral("easyeffects_sink") && si.appName == QStringLiteral("EasyEffects"))) {
          if (si.sinkIndex != PA_INVALID_INDEX) {
            downstreamIdx = si.sinkIndex;
            break;
          }
        }
      }
      if (downstreamIdx != PA_INVALID_INDEX) {
        for (const SinkEntry& s : sinks) {
          if (s.index == downstreamIdx && !s.name.isEmpty()) {
            resolved = s.name;
            break;
          }
        }
      }
    }

    PulseEngine* target = guard.data();
    QMetaObject::invokeMethod(
        target,
        [target, resolved, availMap]() {
          target->applySnapshot(resolved, availMap);
        },
        Qt::QueuedConnection);
  }
};

void snapshotServerInfoCb(pa_context*, const pa_server_info* info, void* userdata) {
  auto* snap = static_cast<std::shared_ptr<PulseSnapshot>*>(userdata);
  if (info && info->default_sink_name) {
    (*snap)->defaultSink = QString::fromUtf8(info->default_sink_name);
  }
  (*snap)->maybeFinish();
  delete snap;
}

void snapshotSinkInfoCb(pa_context*, const pa_sink_info* info, int eol, void* userdata) {
  auto* snap = static_cast<std::shared_ptr<PulseSnapshot>*>(userdata);
  if (eol > 0) {
    (*snap)->maybeFinish();
    delete snap;
    return;
  }
  if (eol < 0) {
    (*snap)->maybeFinish();
    delete snap;
    return;
  }
  if (info && info->name) {
    SinkEntry entry;
    entry.index = info->index;
    entry.name = QString::fromUtf8(info->name);
    if (info->n_ports == 0 || !info->ports) {
      entry.available = true;
    } else {
      bool anyAvail = false;
      for (uint32_t i = 0; i < info->n_ports; ++i) {
        if (info->ports[i] && info->ports[i]->available != PA_PORT_AVAILABLE_NO) {
          anyAvail = true;
          break;
        }
      }
      entry.available = anyAvail;
    }
    (*snap)->sinks.append(entry);
  }
}

void snapshotSinkInputCb(pa_context*, const pa_sink_input_info* info, int eol, void* userdata) {
  auto* snap = static_cast<std::shared_ptr<PulseSnapshot>*>(userdata);
  if (eol != 0) {
    (*snap)->maybeFinish();
    delete snap;
    return;
  }
  if (info) {
    SinkInputEntry e;
    e.index = info->index;
    e.sinkIndex = info->sink;
    if (info->proplist) {
      if (const char* nn = pa_proplist_gets(info->proplist, "node.name")) {
        e.nodeName = QString::fromUtf8(nn);
      }
      if (const char* an = pa_proplist_gets(info->proplist, PA_PROP_APPLICATION_NAME)) {
        e.appName = QString::fromUtf8(an);
      }
    }
    (*snap)->inputs.append(e);
  }
}

struct MoveReq {
  QByteArray targetName;
};

void moveSinkInputsCb(pa_context* c, const pa_sink_input_info* info, int eol, void* userdata) {
  auto* req = static_cast<MoveReq*>(userdata);
  if (eol != 0) {
    delete req;
    return;
  }
  if (!info || !info->proplist) return;
  const char* appName = pa_proplist_gets(info->proplist, PA_PROP_APPLICATION_NAME);
  if (!appName || std::strcmp(appName, "EasyEffects") == 0) return;
  if (pa_operation* op = pa_context_move_sink_input_by_name(c, info->index, req->targetName.constData(), nullptr, nullptr)) {
    pa_operation_unref(op);
  }
}

void moveSourceOutputsCb(pa_context* c, const pa_source_output_info* info, int eol, void* userdata) {
  auto* req = static_cast<MoveReq*>(userdata);
  if (eol != 0) {
    delete req;
    return;
  }
  if (!info) return;
  if (pa_operation* op = pa_context_move_source_output_by_name(c, info->index, req->targetName.constData(), nullptr, nullptr)) {
    pa_operation_unref(op);
  }
}

}  // namespace

PulseEngine::PulseEngine(QObject* parent) : QObject(parent) {
  m_debounceTimer.setInterval(60);
  m_debounceTimer.setSingleShot(true);
  connect(&m_debounceTimer, &QTimer::timeout, this, &PulseEngine::refreshState);
}

PulseEngine::~PulseEngine() {
  teardown();
}

void PulseEngine::start() {
  if (m_started) return;
  if (qEnvironmentVariableIsSet("HYPRVIBE_NO_DAEMONS") ||
      qEnvironmentVariable("QT_QPA_PLATFORM") == QStringLiteral("offscreen")) {
    return;
  }
  m_started = true;

  m_mainloop = pa_threaded_mainloop_new();
  if (!m_mainloop) return;

  pa_mainloop_api* api = pa_threaded_mainloop_get_api(m_mainloop);
  m_context = pa_context_new(api, "hyprvibe-quickshell");
  if (!m_context) {
    teardown();
    return;
  }

  pa_context_set_state_callback(m_context, &PulseEngine::contextStateCb, this);
  if (pa_context_connect(m_context, nullptr, PA_CONTEXT_NOAUTOSPAWN, nullptr) < 0) {
    teardown();
    return;
  }

  if (pa_threaded_mainloop_start(m_mainloop) < 0) {
    teardown();
    return;
  }
}

void PulseEngine::teardown() {
  if (m_mainloop) {
    pa_threaded_mainloop_lock(m_mainloop);
    if (m_context) {
      pa_context_set_state_callback(m_context, nullptr, nullptr);
      pa_context_set_subscribe_callback(m_context, nullptr, nullptr);
      pa_context_disconnect(m_context);
      pa_context_unref(m_context);
      m_context = nullptr;
    }
    m_ready = false;
    pa_threaded_mainloop_unlock(m_mainloop);
    pa_threaded_mainloop_stop(m_mainloop);
    pa_threaded_mainloop_free(m_mainloop);
    m_mainloop = nullptr;
  }
  m_started = false;
}

void PulseEngine::contextStateCb(pa_context* c, void* userdata) {
  auto* self = static_cast<PulseEngine*>(userdata);
  if (!self) return;
  const pa_context_state_t st = pa_context_get_state(c);
  if (st == PA_CONTEXT_READY) {
    self->m_ready = true;
    pa_context_set_subscribe_callback(
        c,
        reinterpret_cast<pa_context_subscribe_cb_t>(&PulseEngine::contextSubscribeCb),
        self);
    if (pa_operation* op = pa_context_subscribe(
            c,
            static_cast<pa_subscription_mask_t>(PA_SUBSCRIPTION_MASK_SINK |
                                                PA_SUBSCRIPTION_MASK_SOURCE |
                                                PA_SUBSCRIPTION_MASK_SINK_INPUT |
                                                PA_SUBSCRIPTION_MASK_SERVER),
            nullptr, nullptr)) {
      pa_operation_unref(op);
    }
    QMetaObject::invokeMethod(self, [self]() { self->refreshState(); }, Qt::QueuedConnection);
  } else if (st == PA_CONTEXT_FAILED || st == PA_CONTEXT_TERMINATED) {
    self->m_ready = false;
  }
}

void PulseEngine::contextSubscribeCb(pa_context*, int, uint32_t, void* userdata) {
  auto* self = static_cast<PulseEngine*>(userdata);
  if (!self) return;
  QMetaObject::invokeMethod(self, [self]() { self->scheduleRefresh(); }, Qt::QueuedConnection);
}

void PulseEngine::scheduleRefresh() {
  if (!m_debounceTimer.isActive()) m_debounceTimer.start();
}

void PulseEngine::refreshState() {
  if (!m_started) start();
  if (!m_mainloop || !m_context || !m_ready) return;

  pa_threaded_mainloop_lock(m_mainloop);
  if (!m_ready || !m_context) {
    pa_threaded_mainloop_unlock(m_mainloop);
    return;
  }

  auto snap = std::make_shared<PulseSnapshot>();
  snap->owner = this;
  snap->guard = this;

  if (pa_operation* op = pa_context_get_server_info(m_context, &snapshotServerInfoCb, new std::shared_ptr<PulseSnapshot>(snap))) {
    pa_operation_unref(op);
  } else {
    snap->maybeFinish();
  }
  if (pa_operation* op = pa_context_get_sink_info_list(m_context, &snapshotSinkInfoCb, new std::shared_ptr<PulseSnapshot>(snap))) {
    pa_operation_unref(op);
  } else {
    snap->maybeFinish();
  }
  if (pa_operation* op = pa_context_get_sink_input_info_list(m_context, &snapshotSinkInputCb, new std::shared_ptr<PulseSnapshot>(snap))) {
    pa_operation_unref(op);
  } else {
    snap->maybeFinish();
  }

  pa_threaded_mainloop_unlock(m_mainloop);
}

void PulseEngine::applySnapshot(const QString& resolvedSink, const QVariantMap& availability) {
  if (m_volumeSinkName == resolvedSink && m_sinkAvailability == availability) return;
  m_volumeSinkName = resolvedSink;
  m_sinkAvailability = availability;
  emit stateUpdated(m_volumeSinkName, m_sinkAvailability);
}

void PulseEngine::setDefaultSink(const QString& sinkName) {
  if (sinkName.isEmpty()) return;
  if (!m_started) start();
  if (!m_mainloop || !m_context || !m_ready) return;

  const QByteArray target = sinkName.toUtf8();
  pa_threaded_mainloop_lock(m_mainloop);
  if (m_ready && m_context) {
    if (pa_operation* op1 = pa_context_set_default_sink(m_context, target.constData(), nullptr, nullptr)) {
      pa_operation_unref(op1);
    }
    auto* req = new MoveReq{target};
    if (pa_operation* op2 = pa_context_get_sink_input_info_list(m_context, &moveSinkInputsCb, req)) {
      pa_operation_unref(op2);
    } else {
      delete req;
    }
  }
  pa_threaded_mainloop_unlock(m_mainloop);
}

void PulseEngine::setDefaultSource(const QString& sourceName) {
  if (sourceName.isEmpty()) return;
  if (!m_started) start();
  if (!m_mainloop || !m_context || !m_ready) return;

  const QByteArray target = sourceName.toUtf8();
  pa_threaded_mainloop_lock(m_mainloop);
  if (m_ready && m_context) {
    if (pa_operation* op1 = pa_context_set_default_source(m_context, target.constData(), nullptr, nullptr)) {
      pa_operation_unref(op1);
    }
    auto* req = new MoveReq{target};
    if (pa_operation* op2 = pa_context_get_source_output_info_list(m_context, &moveSourceOutputsCb, req)) {
      pa_operation_unref(op2);
    } else {
      delete req;
    }
  }
  pa_threaded_mainloop_unlock(m_mainloop);
}
