#ifndef PACKAGES_FLUTTER_WEBRTC_LINUX_TASK_RUNNER_LINUX_H_
#define PACKAGES_FLUTTER_WEBRTC_LINUX_TASK_RUNNER_LINUX_H_

#include <functional>
#include <memory>
#include <mutex>
#include <queue>

using TaskClosure = std::function<void()>;

namespace livekit_client_plugin {

class TaskRunnerLinux {
 public:
  TaskRunnerLinux();
  ~TaskRunnerLinux();

  // TaskRunner implementation.
  void EnqueueTask(TaskClosure task);

 private:
  // The queue, and the lock over it, held apart from the runner itself.
  //
  // A callback handed to a GMainContext cannot be recalled, so one can still
  // be pending when the runner is destroyed — which is precisely what happens
  // when a track is torn down while its audio thread is still posting frames.
  // The runner holds this state by shared_ptr and the callback holds it by
  // weak_ptr, so a late callback finds out it has nothing left to do instead
  // of locking a mutex that no longer exists.
  struct State {
    std::mutex mutex;
    std::queue<TaskClosure> tasks;
    bool alive = true;  // guarded by mutex
  };

  std::shared_ptr<State> state_;
};

}  // namespace livekit_client_plugin

#endif  // PACKAGES_FLUTTER_WEBRTC_LINUX_TASK_RUNNER_LINUX_H_
