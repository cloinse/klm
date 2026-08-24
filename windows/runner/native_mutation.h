#ifndef RUNNER_NATIVE_MUTATION_H_
#define RUNNER_NATIVE_MUTATION_H_

#include <string>

int RunNativeMutation(const std::wstring& request_path,
                      const std::wstring& request_sha256,
                      const std::wstring& response_path);

#endif  // RUNNER_NATIVE_MUTATION_H_
