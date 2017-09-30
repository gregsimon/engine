// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "flutter_window.h"

#include "flutter/common/threads.h"
#include "flutter/fml/platform/darwin/scoped_block.h"
#include "flutter/shell/gpu/gpu_surface_gl.h"
#include "flutter/shell/platform/darwin/common/buffer_conversions.h"
#include "flutter/shell/platform/darwin/desktop/platform_view_mac.h"
#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterChannels.h"
#include "flutter/shell/platform/darwin/ios/framework/Headers/FlutterCodecs.h"
#include "lib/fxl/functional/make_copyable.h"

#include <algorithm>

namespace {

typedef void (^PlatformMessageResponseCallback)(NSData*);

class PlatformMessageResponseDarwin : public blink::PlatformMessageResponse {
  FRIEND_MAKE_REF_COUNTED(PlatformMessageResponseDarwin);

 public:
  void Complete(std::vector<uint8_t> data) override {
    fxl::RefPtr<PlatformMessageResponseDarwin> self(this);
    blink::Threads::Platform()->PostTask(
        fxl::MakeCopyable([ self, data = std::move(data) ]() mutable {
          self->callback_.get()(shell::GetNSDataFromVector(data));
        }));
  }

  void CompleteEmpty() override {
    fxl::RefPtr<PlatformMessageResponseDarwin> self(this);
    blink::Threads::Platform()->PostTask(
        fxl::MakeCopyable([self]() mutable { self->callback_.get()(nil); }));
  }

 private:
  explicit PlatformMessageResponseDarwin(PlatformMessageResponseCallback callback)
      : callback_(callback, fml::OwnershipPolicy::Retain) {}

  fml::ScopedBlock<PlatformMessageResponseCallback> callback_;
};

} // namespace

@interface FlutterWindow ()<NSWindowDelegate>

@property(assign) IBOutlet NSOpenGLView* renderSurface;
@property(getter=isSurfaceSetup) BOOL surfaceSetup;

@end

static inline blink::PointerData::Change PointerChangeFromNSEventPhase(NSEventPhase phase) {
  switch (phase) {
    case NSEventPhaseNone:
      return blink::PointerData::Change::kCancel;
    case NSEventPhaseBegan:
      return blink::PointerData::Change::kDown;
    case NSEventPhaseStationary:
    // There is no EVENT_TYPE_POINTER_STATIONARY. So we just pass a move type
    // with the same coordinates
    case NSEventPhaseChanged:
      return blink::PointerData::Change::kMove;
    case NSEventPhaseEnded:
      return blink::PointerData::Change::kUp;
    case NSEventPhaseCancelled:
      return blink::PointerData::Change::kCancel;
    case NSEventPhaseMayBegin:
      return blink::PointerData::Change::kCancel;
  }
  return blink::PointerData::Change::kCancel;
}

@implementation FlutterWindow {
  std::shared_ptr<shell::PlatformViewMac> _platformView;
  bool _mouseIsDown;
  fml::scoped_nsprotocol<FlutterBasicMessageChannel*> _keyEventChannel;
  fml::scoped_nsprotocol<FlutterBasicMessageChannel*> _systemChannel;
  fml::scoped_nsprotocol<FlutterMethodChannel*> _textInputChannel;
  fml::scoped_nsprotocol<FlutterMethodChannel*> _platformChannel;

  // TODO : handle more than one text field at a time
  int _textInputClient;
  int _compositionBase;
  int _compositionExtent;
  int _selectionBase;
  int _selectionExtent;
  NSMutableString* _text;
}

@synthesize renderSurface = _renderSurface;
@synthesize surfaceSetup = _surfaceSetup;

- (void)awakeFromNib {
  [super awakeFromNib];

  self.delegate = self;

  [self updateWindowSize];
}

- (void)setupPlatformView {
  FXL_DCHECK(_platformView == nullptr) << "The platform view must not already be set.";

  _platformView = std::make_shared<shell::PlatformViewMac>(self.renderSurface);
  _platformView->Attach();
  _platformView->SetupResourceContextOnIOThread();
  _platformView->NotifyCreated(std::make_unique<shell::GPUSurfaceGL>(_platformView.get()));

  _textInputClient = 1;
  _compositionBase = 0;
  _compositionExtent = 0;
  _selectionBase = 0;
  _selectionExtent = 0;
  _text = [[NSMutableString alloc] init];

  _platformChannel.reset([[FlutterMethodChannel alloc]
         initWithName:@"flutter/platform"
      binaryMessenger:self
                codec:[FlutterJSONMethodCodec sharedInstance]]);

  _keyEventChannel.reset([[FlutterBasicMessageChannel alloc]
         initWithName:@"flutter/keyevent"
      binaryMessenger:self
                codec:[FlutterJSONMessageCodec sharedInstance]]);

  _textInputChannel.reset([[FlutterMethodChannel alloc]
         initWithName:@"flutter/textinput"
      binaryMessenger:self
                codec:[FlutterJSONMethodCodec sharedInstance]]);

  _systemChannel.reset([[FlutterBasicMessageChannel alloc]
         initWithName:@"flutter/system"
      binaryMessenger:self
                codec:[FlutterJSONMessageCodec sharedInstance]]);

}

// TODO(eseidel): This does not belong in flutter_window!
// Probably belongs in NSApplicationDelegate didFinishLaunching.
- (void)setupAndLoadDart {
  _platformView->SetupAndLoadDart();
}

- (void)windowDidResize:(NSNotification*)notification {
  [self updateWindowSize];
}

- (void)updateWindowSize {
  [self setupSurfaceIfNecessary];

  blink::ViewportMetrics metrics;
  auto size = self.renderSurface.frame.size;
  metrics.physical_width = size.width;
  metrics.physical_height = size.height;

  blink::Threads::UI()->PostTask([ engine = _platformView->engine().GetWeakPtr(), metrics ] {
    if (engine.get()) {
      engine->SetViewportMetrics(metrics);
    }
  });
}

- (void)setupSurfaceIfNecessary {
  if (self.isSurfaceSetup) {
    return;
  }

  self.surfaceSetup = YES;

  [self setupPlatformView];
  [self setupAndLoadDart];
}

#pragma mark - Responder overrides

- (void)dispatchEvent:(NSEvent*)event phase:(NSEventPhase)phase {
  NSPoint location = [_renderSurface convertPoint:event.locationInWindow fromView:nil];
  location.y = _renderSurface.frame.size.height - location.y;

  blink::PointerData pointer_data;
  pointer_data.Clear();

  constexpr int kMicrosecondsPerSecond = 1000 * 1000;
  pointer_data.time_stamp = event.timestamp * kMicrosecondsPerSecond;
  pointer_data.change = PointerChangeFromNSEventPhase(phase);
  pointer_data.kind = blink::PointerData::DeviceKind::kMouse;
  pointer_data.physical_x = location.x;
  pointer_data.physical_y = location.y;
  pointer_data.pressure = 1.0;
  pointer_data.pressure_max = 1.0;

  switch (pointer_data.change) {
    case blink::PointerData::Change::kDown:
      _mouseIsDown = true;
      break;
    case blink::PointerData::Change::kCancel:
    case blink::PointerData::Change::kUp:
      _mouseIsDown = false;
      break;
    case blink::PointerData::Change::kMove:
      if (!_mouseIsDown)
        pointer_data.change = blink::PointerData::Change::kHover;
      break;
    case blink::PointerData::Change::kAdd:
    case blink::PointerData::Change::kRemove:
    case blink::PointerData::Change::kHover:
      FXL_DCHECK(!_mouseIsDown);
      break;
  }

  blink::Threads::UI()->PostTask([ engine = _platformView->engine().GetWeakPtr(), pointer_data ] {
    if (engine.get()) {
      blink::PointerDataPacket packet(1);
      packet.SetPointerData(0, pointer_data);
      engine->DispatchPointerDataPacket(packet);
    }
  });
}

// Send the (updated) text string to the Flutter dart code. On mobile
// this comes from an IME, here we simulate an IME running on desktop.
- (void)updateText {
  NSDictionary* state = @{
                          @"selectionBase" : @(_selectionBase),
                          @"selectionExtent" : @(_selectionExtent),
                          @"composingBase" : @(_compositionBase),
                          @"composingExtent" : @(_compositionExtent),
                          @"text" : _text,
                        };
  [_textInputChannel.get() invokeMethod:@"TextInputClient.updateEditingState"
                              arguments:@[ @(_textInputClient), state ]];
}

- (void)mouseDown:(NSEvent*)event {
  [self dispatchEvent:event phase:NSEventPhaseBegan];
}

- (void)mouseDragged:(NSEvent*)event {
  [self dispatchEvent:event phase:NSEventPhaseChanged];
}

- (void)mouseUp:(NSEvent*)event {
  [self dispatchEvent:event phase:NSEventPhaseEnded];
}

- (void)deleteBackward:(id)sender {
  NSRange range = NSMakeRange([_text length]-1,1);
  [_text replaceCharactersInRange:range withString:@""];
  _selectionBase = _selectionExtent = [_text length];
  [self updateText];
}

- (void)moveRight:(id)sender {
  _selectionBase = std::max<int>(_selectionBase+1, [_text length]-1);
  [self updateText];
}

- (void)moveLeft:(id)sender {
  _selectionBase--;
  if (_selectionBase < 0)
    _selectionBase = 0;
  _selectionExtent = _selectionBase;
  [self updateText];
}

- (void)insertText:(id)aString {
  // insert @ _compositionBase
  [_text appendString:aString];
  _selectionBase = _selectionExtent = [_text length];
  [self updateText];
}

- (void)keyDown:(NSEvent *)event {
  NSLog(@"keyDown:(NSEvent) 0x%02x %d\n", event.keyCode, event.keyCode);
  // SEE: http://swiftrien.blogspot.com/2015/03/key-bindings-nsresponder-keydown-etc.html
  [self interpretKeyEvents:[NSArray arrayWithObject:event]];
}

- (void)dealloc {
  if (_platformView) {
    _platformView->NotifyDestroyed();
  }

  [super dealloc];
}

// |FlutterBinaryMessenger|
- (void)sendOnChannel:(NSString*)channel message:(NSData* _Nullable)message {
   [self sendOnChannel:channel message:message binaryReply:nil];
}

// |FlutterBinaryMessenger|
- (void)sendOnChannel:(NSString*)channel
              message:(NSData* _Nullable)message
          binaryReply:(FlutterBinaryReply _Nullable)callback {
  NSString* newStr = [[[NSString alloc] initWithData:message
                                         encoding:NSUTF8StringEncoding] autorelease];
  NSLog(@"sendOnChannel: [%@] %@", channel, newStr);
  NSAssert(channel, @"The channel must not be null");

  fxl::RefPtr<PlatformMessageResponseDarwin> response =
      (callback == nil) ? nullptr
                        : fxl::MakeRefCounted<PlatformMessageResponseDarwin>(^(NSData* reply) {
                            callback(reply);
                          });
  fxl::RefPtr<blink::PlatformMessage> platformMessage =
      (message == nil) ? fxl::MakeRefCounted<blink::PlatformMessage>(channel.UTF8String, response)
                       : fxl::MakeRefCounted<blink::PlatformMessage>(
                             channel.UTF8String, shell::GetVectorFromNSData(message), response);
  _platformView->DispatchPlatformMessage(platformMessage);
}

// |FlutterBinaryMessenger|
- (void)setMessageHandlerOnChannel:(NSString*)channel
              binaryMessageHandler:(FlutterBinaryMessageHandler)handler {
  NSAssert(channel, @"The channel must not be null");
  NSLog(@"setMessageHandlerOnChannel");
  //_platformView->platform_message_router().SetMessageHandler(channel.UTF8String, handler);
}

@end
