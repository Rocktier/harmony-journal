import { TimelineRow } from '../data/NoteMeta';

/**
 * 时光时间轴的数据源（`LazyForEach` 用）
 *
 * 为什么要它：家族铁律① —— 长列表必须 `LazyForEach`，只构建可见区域。
 * 而 `LazyForEach` 不认普通数组，必须给一个 `IDataSource`。
 *
 * ⚠️ **踩过的坑（首页刷新靠它）**：
 *   `router.back()` 回到首页时 `aboutToAppear` **不会**重新触发，靠 `onPageShow` 刷新；
 *   而数据换了之后，光替换内部数组**不会**重画 —— 必须调 `listener.onDataReloaded()`，
 *   否则用户编辑完回来看到的是旧列表（与当年"列表不刷新"同一个坑。
 */
export class TimelineDataSource implements IDataSource {
  private rows: TimelineRow[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): TimelineRow {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at: number = this.listeners.indexOf(listener);
    if (at >= 0) {
      this.listeners.splice(at, 1);
    }
  }

  /** 换数据并**通知重画**（不通知 = 界面不更新） */
  reload(rows: TimelineRow[]): void {
    this.rows = rows;
    this.notifyReloaded();
  }

  private notifyReloaded(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
