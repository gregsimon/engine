// Copyright 2017 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_EMBEDDER_H_
#define FLUTTER_EMBEDDER_H_

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

#ifndef FLUTTER_EXPORT
#define FLUTTER_EXPORT
#endif  // FLUTTER_EXPORT

#define FLUTTER_ENGINE_VERSION 1

typedef enum {
  kSuccess = 0,
  kInvalidLibraryVersion,
  kInvalidArguments,
} FlutterResult;

typedef enum {
  kOpenGL,
} FlutterRendererType;

typedef struct _FlutterEngine* FlutterEngine;

typedef bool (*BoolCallback)(void* /* user data */);
typedef uint32_t (*UIntCallback)(void* /* user data */);

typedef struct {
  // The size of this struct. Must be sizeof(FlutterOpenGLRendererConfig).
  size_t struct_size;
  BoolCallback make_current;
  BoolCallback clear_current;
  BoolCallback present;
  UIntCallback fbo_callback;
} FlutterOpenGLRendererConfig;

typedef struct {
  FlutterRendererType type;
  union {
    FlutterOpenGLRendererConfig open_gl;
  };
} FlutterRendererConfig;

typedef struct {
  // The size of this struct. Must be sizeof(FlutterProjectArgs).
  size_t struct_size;
  // The path to the FLX file containing project assets. The string can be
  // collected after the call to |FlutterEngineRun| returns. The string must be
  // NULL terminated.
  const char* assets_path;
  // The path to the Dart file containing the |main| entry point. The string can
  // be collected after the call to |FlutterEngineRun| returns. The string must
  // be NULL terminated.
  const char* main_path;
  // The path to the |.packages| for the project. The string can be collected
  // after the call to |FlutterEngineRun| returns. The string must be NULL
  // terminated.
  const char* packages_path;
} FlutterProjectArgs;

typedef struct {
  // The size of this struct. Must be sizeof(FlutterWindowMetricsEvent).
  size_t struct_size;
  // Physical width of the window.
  size_t width;
  // Physical height of the window.
  size_t height;
  // Scale factor for the physical screen.
  double pixel_ratio;
} FlutterWindowMetricsEvent;

typedef enum {
  kCancel,
  kUp,
  kDown,
  kMove,
} FlutterPointerPhase;

typedef struct {
  // The size of this struct. Must be sizeof(FlutterPointerEvent).
  size_t struct_size;
  FlutterPointerPhase phase;
  size_t timestamp;  // in microseconds.
  double x;
  double y;
} FlutterPointerEvent;

typedef struct {
  // The size of this struct. Must be sizeof(FlutterPlatformMessage).
  size_t struct_size;
  const char* channel;
  const uint8_t* message;
  const size_t message_size;
} FlutterPlatformMessage;

FLUTTER_EXPORT
FlutterResult FlutterEngineRun(size_t version,
                               const FlutterRendererConfig* config,
                               const FlutterProjectArgs* args,
                               void* user_data,
                               FlutterEngine* engine_out);

FLUTTER_EXPORT
FlutterResult FlutterEngineShutdown(FlutterEngine engine);

FLUTTER_EXPORT
FlutterResult FlutterEngineSendWindowMetricsEvent(
    FlutterEngine engine,
    const FlutterWindowMetricsEvent* event);

FLUTTER_EXPORT
FlutterResult FlutterEngineSendPointerEvent(FlutterEngine engine,
                                            const FlutterPointerEvent* events,
                                            size_t events_count);

FLUTTER_EXPORT
FlutterResult FlutterEngineSendPlatformMessage(
    FlutterEngine engine,
    const FlutterPlatformMessage* message);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_EMBEDDER_H_
