#pragma once
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <thread>
#include "onnx_task_engine.h"

class OnnxTaskChannel {
 public:
  OnnxTaskChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~OnnxTaskChannel();
  bool HandleMessage(UINT message);
 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  void Handle(const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result);
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  HWND window_;
  std::thread worker_;
  std::shared_ptr<vitalis::tasks::Control> control_;
  std::unique_ptr<Result> pending_;
  std::string request_id_, failure_;
  Value output_;
};
