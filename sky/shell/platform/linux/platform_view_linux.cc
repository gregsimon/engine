// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "sky/shell/platform/linux/platform_view_linux.h"
#include "sky/shell/gpu/direct/surface_notifications_direct.h"

namespace sky {
namespace shell {

PlatformView* PlatformView::Create(const Config& config) {
  return new PlatformViewLinux(config);
}

PlatformViewLinux::PlatformViewLinux(const Config& config)
    : PlatformView(config), window_(gfx::kNullAcceleratedWidget) {}

PlatformViewLinux::~PlatformViewLinux() {}

void PlatformViewLinux::SurfaceCreated(gfx::AcceleratedWidget widget) {
  DCHECK(window_ == gfx::kNullAcceleratedWidget);
  window_ = widget;
  SurfaceNotificationsDirect::NotifyCreated(config_, window_);
}

void PlatformViewLinux::SurfaceDestroyed(void) {
  DCHECK(window_ != gfx::kNullAcceleratedWidget);
  window_ = gfx::kNullAcceleratedWidget;
  SurfaceNotificationsDirect::NotifyDestroyed(config_);
}

}  // namespace shell
}  // namespace sky
