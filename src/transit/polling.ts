type PollOptions = {
  interval: number;
  maxInterval?: number;
  isVisible: () => boolean;
};

/** Poll serially; false or a rejection means the feed failed, not an empty result. */
export function startPolling(task: (signal: AbortSignal) => Promise<boolean | void>, {
  interval, maxInterval = 60_000, isVisible,
}: PollOptions) {
  const controller = new AbortController();
  let delay = interval;
  let timer: ReturnType<typeof setTimeout>;

  const poll = async () => {
    if (controller.signal.aborted) return;
    if (isVisible()) {
      try {
        const ok = await task(controller.signal);
        delay = ok === false ? Math.min(maxInterval, delay * 2) : interval;
      } catch {
        delay = Math.min(maxInterval, delay * 2);
      }
    }
    if (!controller.signal.aborted) timer = setTimeout(poll, delay);
  };

  timer = setTimeout(poll, 0);
  return () => {
    controller.abort();
    clearTimeout(timer);
  };
}
