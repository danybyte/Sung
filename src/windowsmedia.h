#pragma once

#include "backend.h"

#ifdef Q_OS_WIN
class QWindow;
void registerWindowsMediaControls(Backend *backend, QWindow *window);
#else
inline void registerWindowsMediaControls(Backend *, void *) {}
#endif
