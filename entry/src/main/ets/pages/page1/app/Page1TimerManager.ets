export class TimerManager {
  private readonly timers: Map<string, number> = new Map<string, number>()

  get(name: string): number {
    const v: number | undefined = this.timers.get(name)
    return typeof v === 'number' ? v : -1
  }

  set(name: string, timerId: number): void {
    this.clear(name)
    if (timerId >= 0) {
      this.timers.set(name, timerId)
    }
  }

  clear(name: string): void {
    const oldId: number = this.get(name)
    if (oldId >= 0) {
      try { clearTimeout(oldId) } catch (_) {}
      this.timers.delete(name)
    }
  }

  clearAll(): void {
    const keys: string[] = []
    this.timers.forEach((_v: number, k: string): void => {
      keys.push(k)
    })
    for (let i: number = 0; i < keys.length; i++) {
      this.clear(keys[i])
    }
  }
}
