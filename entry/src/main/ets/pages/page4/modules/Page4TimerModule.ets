export class Page4TimerModule {
  static setManagedTimeout(
    managedTimerIds: Set<number>,
    cb: () => void,
    delayMs: number
  ): number {
    const id: number = setTimeout((): void => {
      managedTimerIds.delete(id)
      cb()
    }, Math.max(0, Math.trunc(delayMs))) as unknown as number
    managedTimerIds.add(id)
    return id
  }

  static clearManagedTimer(managedTimerIds: Set<number>, timerId: number): number {
    if (timerId < 0) return -1
    try { clearTimeout(timerId) } catch (_) {}
    managedTimerIds.delete(timerId)
    return -1
  }

  static clearAllManagedTimers(managedTimerIds: Set<number>): void {
    const ids: Array<number> = []
    managedTimerIds.forEach((id: number): void => { ids.push(id) })
    for (let i: number = 0; i < ids.length; i++) {
      try { clearTimeout(ids[i]) } catch (_) {}
      managedTimerIds.delete(ids[i])
    }
  }
}
