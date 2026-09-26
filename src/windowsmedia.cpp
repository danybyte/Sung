#include "windowsmedia.h"

#ifdef Q_OS_WIN

#include <QTimer>
#include <QWindow>
#include <windows.h>
#include <systemmediatransportcontrolsinterop.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/base.h>

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Media;

namespace {

class WindowsMediaControls final : public QObject {
public:
  WindowsMediaControls(Backend *backend, QWindow *window)
      : QObject(backend), b(backend) {
    auto factory = get_activation_factory<SystemMediaTransportControls,
                                          ISystemMediaTransportControlsInterop>();
    check_hresult(factory->GetForWindow(
        reinterpret_cast<HWND>(window->winId()),
        guid_of<SystemMediaTransportControls>(),
        reinterpret_cast<void **>(put_abi(controls))));

    controls.IsEnabled(true);
    controls.IsPlayEnabled(true);
    controls.IsPauseEnabled(true);
    controls.IsStopEnabled(true);
    controls.IsNextEnabled(true);
    controls.IsPreviousEnabled(true);

    buttonToken = controls.ButtonPressed(
        [this](SystemMediaTransportControls const &,
               SystemMediaTransportControlsButtonPressedEventArgs const &args) {
          const auto button = args.Button();
          QMetaObject::invokeMethod(this, [this, button] {
            switch (button) {
            case SystemMediaTransportControlsButton::Play: b->play(); break;
            case SystemMediaTransportControlsButton::Pause: b->pause(); break;
            case SystemMediaTransportControlsButton::Stop: b->stop(); break;
            case SystemMediaTransportControlsButton::Next: b->next(); break;
            case SystemMediaTransportControlsButton::Previous: b->previous(); break;
            default: break;
            }
          }, Qt::QueuedConnection);
        });

    connect(b, &Backend::trackChanged, this, &WindowsMediaControls::update);
    connect(b, &Backend::playbackChanged, this, &WindowsMediaControls::update);
    connect(b, &Backend::positionChanged, this, &WindowsMediaControls::updateTimeline);

    timer.setInterval(1000);
    connect(&timer, &QTimer::timeout, this, &WindowsMediaControls::updateTimeline);
    timer.start();
    update();
  }

  ~WindowsMediaControls() override {
    if (controls) controls.ButtonPressed(buttonToken);
  }

private:
  void update() {
    const auto current = b->current();
    auto updater = controls.DisplayUpdater();
    updater.ClearAll();
    updater.Type(MediaPlaybackType::Music);
    if (!current.isEmpty()) {
      auto music = updater.MusicProperties();
      music.Title(current.value("title").toString().toStdWString());
      music.Artist(current.value("artist").toString().toStdWString());
      music.AlbumTitle(current.value("album").toString().toStdWString());
    }
    updater.Update();

    controls.PlaybackStatus(
        b->playing() ? MediaPlaybackStatus::Playing
        : b->stopped() || current.isEmpty() ? MediaPlaybackStatus::Stopped
                                            : MediaPlaybackStatus::Paused);
    controls.IsNextEnabled(b->queue()->count() > 0);
    controls.IsPreviousEnabled(b->queue()->count() > 0);
    updateTimeline();
  }

  void updateTimeline() {
    if (!controls || b->duration() <= 0) return;
    SystemMediaTransportControlsTimelineProperties timeline;
    timeline.StartTime(TimeSpan{0});
    timeline.EndTime(TimeSpan{b->duration() * 10000});
    timeline.Position(TimeSpan{b->position() * 10000});
    controls.UpdateTimelineProperties(timeline);
  }

  Backend *b;
  SystemMediaTransportControls controls{nullptr};
  event_token buttonToken{};
  QTimer timer;
};

} // namespace

void registerWindowsMediaControls(Backend *backend, QWindow *window) {
  try {
    new WindowsMediaControls(backend, window);
  } catch (const hresult_error &) {
    // SMTC is optional: older Windows versions and restricted sessions can
    // reject activation, but playback must continue normally.
  }
}

#endif
