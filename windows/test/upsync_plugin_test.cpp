#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "upsync_plugin.h"

namespace upsync {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(UpsyncPlugin, GetPathsReturnsExpectedKeys) {
  UpsyncPlugin plugin;
  EncodableValue result_value;
  plugin.HandleMethodCall(
      MethodCall("getPaths", std::make_unique<EncodableValue>(EncodableMap{})),
      std::make_unique<MethodResultFunctions<>>(
          [&result_value](const EncodableValue* result) {
            result_value = *result;
          },
          nullptr, nullptr));

  const auto* result_map = std::get_if<EncodableMap>(&result_value);
  ASSERT_NE(result_map, nullptr);

  const auto executable_path =
      result_map->find(EncodableValue("currentExecutablePath"));
  ASSERT_NE(executable_path, result_map->end());
  ASSERT_TRUE(std::holds_alternative<std::string>(executable_path->second));
  EXPECT_FALSE(std::get<std::string>(executable_path->second).empty());

  const auto executable_name =
      result_map->find(EncodableValue("currentExecutableName"));
  ASSERT_NE(executable_name, result_map->end());
  ASSERT_TRUE(std::holds_alternative<std::string>(executable_name->second));
  EXPECT_FALSE(std::get<std::string>(executable_name->second).empty());

  const auto updates_directory =
      result_map->find(EncodableValue("updatesDirectory"));
  ASSERT_NE(updates_directory, result_map->end());
  ASSERT_TRUE(std::holds_alternative<std::string>(updates_directory->second));
}

TEST(UpsyncPlugin, ApplyUpdateAndRestartReturnsFalseWithoutArgs) {
  UpsyncPlugin plugin;
  bool result_value = true;
  plugin.HandleMethodCall(
      MethodCall("applyUpdateAndRestart", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_value](const EncodableValue* result) {
            result_value = std::get<bool>(*result);
          },
          nullptr, nullptr));

  EXPECT_FALSE(result_value);
}

}  // namespace test
}  // namespace upsync
