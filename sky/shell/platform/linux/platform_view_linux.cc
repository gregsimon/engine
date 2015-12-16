// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "sky/shell/platform/linux/platform_view_linux.h"
#include "sky/shell/gpu/direct/surface_notifications_direct.h"

#include <stdio.h>

namespace sky {
namespace shell {

static GtkWidget *window=NULL;
static GtkWidget *da=NULL;
static GdkWindow *DrawingWindow=NULL;
static Window X_window;
static Display *X_display;
static GLXContext X_context;
static XVisualInfo *X_visual;
static XWindowAttributes X_attributes;
static GLint attributes[] = { GLX_RGBA, GLX_DEPTH_SIZE, 24, GLX_DOUBLEBUFFER, None};


PlatformView* PlatformView::Create(const Config& config) {
  return new PlatformViewLinux(config);
}

void close_program()
{
   //timer can trigger warnings when closing program.
   printf("Quit Program\n");
   gtk_main_quit();
}

static void configureGL(GtkWidget *da, gpointer data)
{
   printf("Configure GL\n");
   DrawingWindow=gtk_widget_get_window(GTK_WIDGET(da));

   X_window=gdk_x11_window_get_xid(GDK_WINDOW(DrawingWindow));
   X_display=gdk_x11_get_default_xdisplay();
   X_visual=glXChooseVisual(X_display, 0, attributes);
   X_context=glXCreateContext(X_display, X_visual, NULL, GL_TRUE);

   XGetWindowAttributes(X_display, X_window, &X_attributes);
   glXMakeCurrent(X_display, X_window, X_context);
   XMapWindow(X_display, X_window);
   printf("Viewport %i %i\n", (int)X_attributes.width, (int)X_attributes.height);
   glViewport(0, 0, X_attributes.width, X_attributes.height);
   glOrtho(-10,10,-10,10,-10,10);
   glScalef(5.0, 5.0, 5.0);
}

PlatformViewLinux::PlatformViewLinux(const Config& config)
    : PlatformView(config), window_(gfx::kNullAcceleratedWidget)
{
  window=gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(window), 500, 500);
  da=gtk_drawing_area_new();
  // TODO gtk_widget_set_double_buffered(da, FALSE);

  gtk_container_add(GTK_CONTAINER(window), da);
  g_signal_connect_swapped(window, "destroy", G_CALLBACK(close_program), NULL);

  gtk_widget_show(window);

  g_signal_connect(da, "configure-event", G_CALLBACK(configureGL), NULL);
  //g_signal_connect(da, "draw", G_CALLBACK(drawGL), NULL);

  gtk_widget_show_all(window);

}

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
