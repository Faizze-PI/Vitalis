#include "onnx_task_channel.h"
#include <flutter/standard_method_codec.h>
#include <regex>

// HC-083: worker completion is delivered on Flutter's platform thread.
namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
constexpr UINT kTaskCompleted = WM_APP + 83;
const Value& Field(const Map& map, const char* key) {
  const auto found = map.find(Value(key));
  if (found == map.end()) throw vitalis::tasks::Failure{"invalidTaskRequest"};
  return found->second;
}
std::string Text(const Map& map, const char* key) {
  return std::get<std::string>(Field(map, key));
}
int64_t Integer(const Value& value) {
  if (const auto* number = std::get_if<int32_t>(&value)) return *number;
  return std::get<int64_t>(value);
}
double Number(const Value& value) {
  if (const auto* number = std::get_if<double>(&value)) return *number;
  return static_cast<double>(Integer(value));
}
vitalis::tasks::Request Parse(const Map& args) {
  vitalis::tasks::Request request;
  request.root = std::filesystem::u8path(Text(args, "appSupportPath"));
  request.hash = Text(args, "modelSha256");
  request.input_id = Text(args, "inputId");
  request.input_name = Text(args, "inputName");
  request.kind = Text(args, "kind");
  if (args.count(Value("modelId"))) request.model_id = Text(args, "modelId");
  if (args.count(Value("modelPackageId"))) request.package_id = Text(args, "modelPackageId");
  for (const auto& value : std::get<flutter::EncodableList>(Field(args, "shape")))
    request.shape.push_back(Integer(value));
  for (const auto& value : std::get<flutter::EncodableList>(Field(args, "outputs")))
    request.outputs.push_back(std::get<std::string>(value));
  if (request.kind == "csv") {
    const auto& values = Field(args, "values");
    if (const auto* floats = std::get_if<std::vector<float>>(&values)) request.values = *floats;
    else for (const auto& value : std::get<flutter::EncodableList>(values))
      request.values.push_back(static_cast<float>(Number(value)));
  } else if (request.kind == "image") {
    const auto& image = std::get<Map>(Field(args, "image"));
    if (Text(image, "resize") != "stretch" || Text(image, "interpolation") != "nearest" ||
        Text(image, "color_order") != "RGB" || Text(image, "orientation") != "stored")
      throw vitalis::tasks::Failure{"imageContract"};
    request.image.layout = Text(image, "layout");
    request.image.scale = Number(Field(image, "scale"));
    for (const auto& value : std::get<flutter::EncodableList>(Field(image, "mean")))
      request.image.mean.push_back(Number(value));
    for (const auto& value : std::get<flutter::EncodableList>(Field(image, "std")))
      request.image.deviation.push_back(Number(value));
  } else throw vitalis::tasks::Failure{"inputContract"};
  return request;
}
}
OnnxTaskChannel::OnnxTaskChannel(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "vitalis/custom_tasks", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    Handle(call, std::move(result));
  });
}
OnnxTaskChannel::~OnnxTaskChannel() {
  channel_->SetMethodCallHandler(nullptr);
  try { if (control_) control_->Cancel(); } catch (...) { /* Worker retains ownership. */ }
  if (worker_.joinable()) worker_.join();
}
void OnnxTaskChannel::Handle(const flutter::MethodCall<Value>& call,
                             std::unique_ptr<Result> result) {
  try {
    if (call.method_name() == "limits") {
      const auto budget = vitalis::tasks::AllocationBudget();
      result->Success(Value(Map{
        {Value("maxModelBytes"), Value(static_cast<int64_t>(budget))},
        {Value("maxInputElements"), Value(static_cast<int64_t>(budget / sizeof(float)))},
        {Value("maxTextBytes"), Value(static_cast<int64_t>(budget / 4))}})); return;
    }
    if (call.arguments() == nullptr) throw vitalis::tasks::Failure{"invalidTaskRequest"};
    const auto& args = std::get<Map>(*call.arguments());
    const auto id = Text(args, "requestId");
    if (!std::regex_match(id, std::regex("[a-f0-9]{32}")))
      throw vitalis::tasks::Failure{"invalidTaskRequest"};
    if (call.method_name() == "cancel") {
      if (pending_ && request_id_ == id) control_->Cancel();
      result->Success(); return; // Intent only; Run resolves after native cleanup.
    }
    if (call.method_name() != "run") { result->NotImplemented(); return; }
    if (pending_) { result->Error("runtimeBusy", "Another task is running."); return; }
    const auto request = Parse(args);
    request_id_ = id;
    control_ = std::make_shared<vitalis::tasks::Control>();
    failure_.clear();
    pending_ = std::move(result);
    try { worker_ = std::thread([this, request, id, control = control_] {
      try {
        const auto outputs = vitalis::tasks::Run(request, *control);
        flutter::EncodableList rows;
        for (const auto& output : outputs) {
          rows.emplace_back(Map{{Value("name"), Value(output.name)},
            {Value("shape"), Value(output.shape)}, {Value("values"), Value(output.values)}});
        }
        control->Check();
        output_ = Value(Map{{Value("requestId"), Value(id)},
          {Value("backend"), Value("ONNX CPU")}, {Value("outputs"), Value(rows)}});
      } catch (const vitalis::tasks::Failure& failure) { failure_ = failure.code; }
        catch (...) { failure_ = control->cancelled.load() ? "cancelled" : "executionFailed"; }
      PostMessageW(window_, kTaskCompleted, 0, 0);
    }); } catch (...) {
      result = std::move(pending_);
      control_.reset();
      throw;
    }
  } catch (const vitalis::tasks::Failure& failure) {
    result->Error(failure.code, "Task request could not be admitted.");
  } catch (...) { result->Error("invalidTaskRequest", "Task request could not be admitted."); }
}
bool OnnxTaskChannel::HandleMessage(UINT message) {
  if (message != kTaskCompleted) return false;
  if (worker_.joinable()) worker_.join();
  if (!pending_) return true;
  auto result = std::move(pending_);
  if (control_->cancelled.load()) failure_ = "cancelled";
  control_.reset();
  if (failure_.empty()) result->Success(output_);
  else result->Error(failure_, "Task ended. Check the declared model/input contract.");
  output_ = Value();
  return true;
}
