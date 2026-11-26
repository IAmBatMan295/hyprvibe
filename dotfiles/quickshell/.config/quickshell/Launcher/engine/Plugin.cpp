#include "LauncherModel.hpp"

#include <QQmlExtensionPlugin>
#include <qqml.h>

class HyprVibeLauncherPlugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
  void registerTypes(const char* uri) override {
    qmlRegisterType<LauncherModel>(uri, 1, 0, "LauncherModel");
  }
};

#include "Plugin.moc"
