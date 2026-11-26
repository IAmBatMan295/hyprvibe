#pragma once

#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantMap>

struct pa_context;
struct pa_threaded_mainloop;

// Event-driven in-process PulseAudio / PipeWire-Pulse controller.
// Replaces periodic `pactl` / `wpctl` / `awk` shell workers with native C callbacks:
// - Resolves virtual DSP volume sinks (e.g., speaker tuning / EasyEffects) to hardware sink
// - Tracks sink port availability (`not available`) on Pulse subscribe events
// - Sets default sink/source and moves application streams in microseconds
class PulseEngine : public QObject {
  Q_OBJECT

public:
  explicit PulseEngine(QObject* parent = nullptr);
  ~PulseEngine() override;

  void start();

  QString volumeSinkName() const { return m_volumeSinkName; }
  QVariantMap sinkAvailability() const { return m_sinkAvailability; }

  void setDefaultSink(const QString& sinkName);
  void setDefaultSource(const QString& sourceName);

public slots:
  void refreshState();
  void applySnapshot(const QString& resolvedSink, const QVariantMap& availability);

signals:
  void stateUpdated(const QString& volumeSinkName, const QVariantMap& sinkAvailability);

private slots:
  void scheduleRefresh();

private:
  void teardown();

  static void contextStateCb(pa_context* c, void* userdata);
  static void contextSubscribeCb(pa_context* c, int type, uint32_t idx, void* userdata);

  pa_threaded_mainloop* m_mainloop = nullptr;
  pa_context* m_context = nullptr;
  bool m_ready = false;
  bool m_started = false;
  QTimer m_debounceTimer;
  QString m_volumeSinkName;
  QVariantMap m_sinkAvailability;
};
