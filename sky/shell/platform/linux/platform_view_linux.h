// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef SKY_SHELL_PLATFORM_VIEW_LINUX_H_
#define SKY_SHELL_PLATFORM_VIEW_LINUX_H_

#include "sky/shell/platform_view.h"

namespace sky {
namespace shell {

class PlatformViewLinux : public PlatformView {
 public:
  explicit PlatformViewLinux(const Config& config);
  ~PlatformViewLinux() override;
  void SurfaceCreated(gfx::AcceleratedWidget widget);
  void SurfaceDestroyed(void);

 private:
  gfx::AcceleratedWidget window_;

  DISALLOW_COPY_AND_ASSIGN(PlatformViewLinux);
};

}  // namespace shell
}  // namespace sky

#endif  // SKY_SHELL_PLATFORM_VIEW_LINUX_H_
