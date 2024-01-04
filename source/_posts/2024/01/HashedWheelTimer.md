---
title: Netty HashedWheelTimer
date: 2024-01-01 15:11:23
categories:
  - [JAVA, Netty]
tags:
  - netty
  - util
  - TimeWheel
---

## 时间轮

定时器对于故障恢复、基于速率的流量控制、调度算法等场景非常重要。而时间轮是一种实现定时器的巧妙算法。它应用范围非常广泛，各种操作系统的定时任务调度都有用到，我们熟悉的 linux crontab，以及 Java 开发过程中常用的 Dubbo、Netty、Quartz、ZooKeeper、Kafka 等，几乎所有和时间任务调度都采用了时间轮的思想。

例如：在[DUBBO](https://cn.dubbo.apache.org/zh-cn/overview/quickstart/)的源码，就曾出现在[失败重试](https://github.com/apache/dubbo/blob/3.2/dubbo-cluster/src/main/java/org/apache/dubbo/rpc/cluster/support/FailbackClusterInvoker.java)的场景中；[异步调用超时检测](https://github.com/apache/dubbo/blob/3.2/dubbo-remoting/dubbo-remoting-api/src/main/java/org/apache/dubbo/remoting/exchange/support/DefaultFuture.java)也常见到其身影。

本文介绍的[io.netty.util.HashedWheelTimer](https://github.com/netty/netty/blob/4.1/common/src/main/java/io/netty/util/HashedWheelTimer.java)是来自`netty-common`包的工具类。

<!-- more -->

### 接口概览

在介绍它的使用前，先了解一下它的类关系图。

{% asset_img HashedWheelTimer.jpg 类关系图 %}

从面向接口编程的角度，我们其实不需要关心`HashedWheelTimer`，只需要关心接口类`Timer`就可以了。该接口内仅有以下两个方法：

```java
public interface Timer {

    // 创建一个定时任务
    Timeout newTimeout(TimerTask task, long delay, TimeUnit unit);

    // 停止所有还没有被执行的定时任务
    Set<Timeout> stop();
}
```

`Timer`是我们要使用的任务调度器，从其方法上可以看出，它提交一个定时任务`TimerTask`，返回的是一个`Timeout`实例。三者间关系类似这样：

{% asset_img Timer.jpg %}

`TimerTask`更简单，就一个`run()`方法，我们可以实现它，自定义需要定时执行的任务：

```java
public interface TimerTask {

    // 自定义定时任务逻辑
    void run(Timeout timeout) throws Exception;
}
```

`Timeout`也是一个接口类，它持有上层的`Timer`调度器实例和下层的`TimerTask`定时任务实例，还可以取消任务的执行。

```java
public interface Timeout {

    Timer timer();

    // 返回此句柄关联的 TimerTask
    TimerTask task();

    // 此句柄关联的 TimerTask 是否已过期
    boolean isExpired();

    // 此句柄关联的 TimerTask 是否已取消
    boolean isCancelled();

    // 取消此句柄关联的 TimerTask
    boolean cancel();
}
```

### 如何使用

有了上面介绍的接口信息，其实我们很容易就可以使用它了。先来一个示例尝尝鲜：

```java
public class HashedWheelTimerTest {

    public static void main(String[] args) {
        Timer timer = new HashedWheelTimer();
        System.out.println(System.currentTimeMillis() );

        // 提交一个任务，让它在 3s 后执行
        Timeout timeout1 = timer.newTimeout(new TimerTask() {
            @Override
            public void run(Timeout timeout) {
                System.out.println(System.currentTimeMillis() + " 3s后执行该任务");
            }
        }, 3, TimeUnit.SECONDS);

        // 再提交一个任务，让它在 5s 后执行
        Timeout timeout2 = timer.newTimeout(new TimerTask() {
            @Override
            public void run(Timeout timeout) {
                System.out.println(System.currentTimeMillis() + " 5s后执行该任务");
            }
        }, 5, TimeUnit.SECONDS);

        // 取消掉那个 3s 后执行的任务
        if (!timeout1.isExpired()) {
            timeout1.cancel();
        }

        // 原来那个 3s 后执行的任务，已经取消了。这里我们反悔了，我们要让这个任务在 4s 后执行
        // 由于 timeout 持有上、下层的实例，所以下面的 timer 也可以写成 timeout1.timer()
        timer.newTimeout(timeout1.task(), 4, TimeUnit.SECONDS);
    }
}
```

### 如何实现

想必大家知道，它内部用的是一个叫做[时间轮](http://www.cse.wustl.edu/~cdgill/courses/cs6874/TimingWheels.ppt)的算法。

{% asset_img HashedWheelTimerDemo.jpg %}

这里先说说大致的执行流程，之后再进行细致的源码分析。

假设轮子有 8 个刻度，默认时钟每 100ms 滴答一下（tick），往前走一格，走完一圈（过了 800ms）以后继续下一圈。把它想象成生活中的钟表就可以了。

内部使用一个长度为 8 的数组存储，数组元素（bucket）的数据结构是链表，链表每个元素代表一个任务，也就是我们前面介绍的`Timeout`的实例。

提交任务的线程，只要把任务往任务队列中存放即可返回。工作线程是单线程，一旦开启，不停地在时钟上绕圈圈，每滴答一下，先将队列中的任务取出，计算其剩余轮次，并转移到对应 tick 的桶中存储；接着取出该 tick 桶中存储的任务，如果轮次为 0 则立即执行，否则轮次-1 后重新插入定时器，等待触发执行。

结合上图示例，看下面的详细介绍：

工作线程到达每个时间整点的时候，开始工作。在`HashedWheelTimer`中，时间都是相对时间，工作线程的启动时间，定义为时间的 0 值。因为一次 tick 是 100ms(默认值)，所以 100ms、200ms、300ms... 就是这些整点。

如上图，当时间到 200ms 的时候，发现任务队列有任务，取出所有的任务。按照任务指定的执行时间，将其分配到相应的 bucket 中。如上图中，{% label info@小蓝 %}和<span style="color: orange;">小橙</span>指定的时间为 100ms~200ms 这个区间，就被分配到第二个 bucket 中，形成链表，其他任务同理。

当然这里还有轮次的概念，比如<span style="color: orange;">小橙</span>指定的时间可能是 150ms + (8\*100ms) = 950ms，它也会落在这个 bucket 中，但是它是下一个轮次才能被执行的。

任务分配到 bucket 完成后，执行该次 tick 的真正的任务，也就是落在第二个 bucket 中的任务{% label info@小蓝 %}和<span style="color: orange;">小橙</span>。

假设执行这两个任务共消耗了 50ms，到达 250ms 的时间点，那么工作线程会休眠 50ms，等待进入到 300ms 这个整点。如果这两个任务执行的时间超过 100ms ，那么其他任务的执行时间有可能会被推迟，因此我们需要注意不要运行耗时任务，比如：IO 处理、休眠等待等。

#### 实例化

接下来，先从它的默认构造器开始分析：

```java io.netty.util.HashedWheelTimer
/**
 * threadFactory: 创建工作线程的线程工厂
 * tickDuration 和 unit 定义了一格的时间长度，默认为 100ms
 * ticksPerWheel: 定义了一圈有多少格，默认为 512
 * maxPendingTimeouts：最大允许等待的 Timeout 实例数，也就是我们可以设置不允许太多的任务等待。
 *                     如果未执行任务数达到阈值，那么再次提交任务会抛出 RejectedExecutionException 异常。默认不限制
 */
public HashedWheelTimer(ThreadFactory threadFactory, long tickDuration, TimeUnit unit, int ticksPerWheel,
        boolean leakDetection, long maxPendingTimeouts) {
    ObjectUtil.checkNotNull(threadFactory, "threadFactory");
    ObjectUtil.checkNotNull(unit, "unit");
    ObjectUtil.checkPositive(tickDuration, "tickDuration");
    ObjectUtil.checkPositive(ticksPerWheel, "ticksPerWheel");

    // 初始化时间轮，这里向上"取整"，保持数组长度为2的n次方
    wheel = createWheel(ticksPerWheel);
    mask = wheel.length - 1; // 掩码，用于快速计算桶号

    // 转换 tickDuration 为纳秒
    long duration = unit.toNanos(tickDuration);

    // 防止溢出
    if (duration >= Long.MAX_VALUE / wheel.length) {
        throw new IllegalArgumentException(String.format(
                "tickDuration: %d (expected: 0 < tickDuration in nanos < %d",
                tickDuration, Long.MAX_VALUE / wheel.length));
    }

    if (duration < MILLISECOND_NANOS) {
        logger.warn("Configured tickDuration {} smaller then {}, using 1ms.",
                    tickDuration, MILLISECOND_NANOS);
        this.tickDuration = MILLISECOND_NANOS;
    } else {
        this.tickDuration = duration;
    }
    // 创建工作线程，后续第一次提交任务时启动线程并设置时间轮开始时间
    workerThread = threadFactory.newThread(worker);

    leak = leakDetection || !workerThread.isDaemon() ? leakDetector.track(this) : null;

    this.maxPendingTimeouts = maxPendingTimeouts;
    // 如果实例化超过 64 个实例，它会打印错误日志提醒你
    if (INSTANCE_COUNTER.incrementAndGet() > INSTANCE_COUNT_LIMIT &&
        WARNED_TOO_MANY_INSTANCES.compareAndSet(false, true)) {
        reportTooManyInstances();
    }
}
```

上面，`HashedWheelTimer`完成了初始化，初始化了时间轮数组`HashedWheelBucket[]`，稍微看一下内部类`HashedWheelBucket`，可以看到它是一个链表的结构。这个很好理解，因为每一格可能有多个任务。

#### 提交任务

```java io.netty.util.HashedWheelTimer
public Timeout newTimeout(TimerTask task, long delay, TimeUnit unit) {
    if (task == null) {
        throw new NullPointerException("task");
    }
    if (unit == null) {
        throw new NullPointerException("unit");
    }

    // 校验等待任务数是否达到阈值 maxPendingTimeouts
    long pendingTimeoutsCount = pendingTimeouts.incrementAndGet();
    if (maxPendingTimeouts > 0 && pendingTimeoutsCount > maxPendingTimeouts) {
        pendingTimeouts.decrementAndGet();
        throw new RejectedExecutionException("Number of pending timeouts ("
            + pendingTimeoutsCount + ") is greater than or equal to maximum allowed pending "
            + "timeouts (" + maxPendingTimeouts + ")");
    }

    // 启动工作线程
    start();

    // deadline是一个相对时间，相对于 HashedWheelTimer 的启动时间
    long deadline = System.nanoTime() + unit.toNanos(delay) - startTime;

    // Guard against overflow.
    if (delay > 0 && deadline < 0) {
        deadline = Long.MAX_VALUE;
    }
    // Timeout实例，一个上层依赖 timer，一个下层依赖 task，另一个是任务截止时间
    HashedWheelTimeout timeout = new HashedWheelTimeout(this, task, deadline);
    timeouts.add(timeout);
    return timeout;
}
```

提交任务的操作非常简单，实例化`Timeout`，然后放到任务队列中。

我们可以看到，这里使用的优先级队列是一个 MPSC（Multiple Producer Single Consumer）的队列，刚好适用于这里的多生产线程，单消费线程的场景。而在 Dubbo 中，使用的队列是`LinkedBlockingQueue`，它是一个以链表方式组织的线程安全队列。

另外就是注意这里调用的`start()`方法，如果该任务是第一个提交的任务，它会负责工作线程的启动。

```java
public void start() {
    switch (WORKER_STATE_UPDATER.get(this)) {
        case WORKER_STATE_INIT: // 首次初始化，则启动工作线程
            if (WORKER_STATE_UPDATER.compareAndSet(this, WORKER_STATE_INIT, WORKER_STATE_STARTED)) {
                workerThread.start();
            }
            break;
        case WORKER_STATE_STARTED: // 已启动无需处理
            break;
        case WORKER_STATE_SHUTDOWN: // 已关闭不可重启
            throw new IllegalStateException("cannot be started once stopped");
        default:
            throw new Error("Invalid WorkerState");
    }

    // 等待直到startTime被worker初始化
    while (startTime == 0) { // 等待通知经典范式，防止虚假唤醒（比如线程中断）
        try {
            startTimeInitialized.await();
        } catch (InterruptedException ignore) {
            // Ignore - it will be ready very soon.
        }
    }
}
```

#### 线程开始工作

```java io.netty.util.HashedWheelTimer.Worker
private final class Worker implements Runnable {
    // 用于暂存stop后仍未处理的Timeout
    private final Set<Timeout> unprocessedTimeouts = new HashSet<Timeout>();

    // tick过的次数，前面说过时针每100ms tick一次
    private long tick;

    @Override
    public void run() {
        // 初始化开始时间startTime。在时间轮中，用的都是相对时间，所以需要以首次启动时间作为基准
        startTime = System.nanoTime();
        if (startTime == 0) {
            // We use 0 as an indicator for the uninitialized value here, so make sure it's not 0 when initialized.
            startTime = 1;
        }

        // 第一个提交任务的线程正 await 呢，唤醒它
        startTimeInitialized.countDown();

        do {
            // 从开始时间和当前刻度数计算下次tick的目标nanoTime，然后等待，直到达到该目标
            final long deadline = waitForNextTick();
            if (deadline > 0) { // 下次tick已到
                int idx = (int) (tick & mask); // 计算该次tick格号
                processCancelledTasks(); // 先处理已被取消的任务
                HashedWheelBucket bucket = wheel[idx]; // 取出该格关联的桶
                transferTimeoutsToBuckets(); // 转移任务队列中的Timeout到对应桶
                bucket.expireTimeouts(deadline); // 执行进入到该桶中的任务
                tick++;
            }
        } while (WORKER_STATE_UPDATER.get(HashedWheelTimer.this) == WORKER_STATE_STARTED);

        // 到这里，说明这个 timer 要关闭了，做一些善后清理工作
        for (HashedWheelBucket bucket: wheel) {
            // 将所有桶中未过期或未取消的任务添加到unprocessedTimeouts
            bucket.clearTimeouts(unprocessedTimeouts);
        }
        for (;;) {
            HashedWheelTimeout timeout = timeouts.poll();
            if (timeout == null) {
                break;
            }
            // 将队列中所有未取消的任务添加到unprocessedTimeouts
            if (!timeout.isCancelled()) {
                unprocessedTimeouts.add(timeout);
            }
        }
        processCancelledTasks(); // 处理已被取消的任务
    }

    private void transferTimeoutsToBuckets() {
        // 单次允许转移的最大个数。 每个tick 100000个Timeout，以防止线程在循环中添加新Timeout时使工作线程过时
        for (int i = 0; i < 100000; i++) {
            HashedWheelTimeout timeout = timeouts.poll();
            if (timeout == null) {
                // 任务队列中没有新Timeout
                break;
            }
            if (timeout.state() == HashedWheelTimeout.ST_CANCELLED) {
                // 还未来得及转移，其间被取消
                continue;
            }

            // 假设这里就是上面示例中的小橙（950ms），calculated = 9，工作线程刚启动执行第一个tick
            long calculated = timeout.deadline / tickDuration;
            timeout.remainingRounds = (calculated - tick) / wheel.length; // 这里算出剩余轮次=1

            final long ticks = Math.max(calculated, tick); // 确保我们不会安排过去的事情
            int stopIndex = (int) (ticks & mask); // 放入的格号=1

            HashedWheelBucket bucket = wheel[stopIndex]; // 找格号对应的桶，插入链表尾部
            bucket.addTimeout(timeout);
        }
    }

    private void processCancelledTasks() {
        for (;;) {
            // 循环处理已被用户cancel()掉的Timeout
            HashedWheelTimeout timeout = cancelledTimeouts.poll();
            if (timeout == null) {
                // 所有的均已处理完毕
                break;
            }
            try {
                timeout.remove(); // 在对应的桶中剔除掉自己
            } catch (Throwable t) {
                if (logger.isWarnEnabled()) {
                    logger.warn("An exception was thrown while process a cancellation task", t);
                }
            }
        }
    }

    private long waitForNextTick() {
        long deadline = tickDuration * (tick + 1); // 第一次进来，deadline=100ms；第二次进来，deadline=200ms

        for (;;) {
            final long currentTime = System.nanoTime() - startTime;
            long sleepTimeMs = (deadline - currentTime + 999999) / 1000000; // 计算要睡的毫秒数（当前时间到截止时间还需要的毫秒数）

            if (sleepTimeMs <= 0) {
                if (currentTime == Long.MIN_VALUE) { // 时钟回拨则不tick
                    return -Long.MAX_VALUE;
                } else {
                    return currentTime; // 已到tick时间
                }
            }

            // Check if we run on windows, as if thats the case we will need
            // to round the sleepTime as workaround for a bug that only affect
            // the JVM if it runs on windows.
            //
            // See https://github.com/netty/netty/issues/356
            if (PlatformDependent.isWindows()) {
                sleepTimeMs = sleepTimeMs / 10 * 10; // windows平台则取整（相当于丢弃最后一位数）
            }

            try {
                Thread.sleep(sleepTimeMs); // 未到时间则休眠
            } catch (InterruptedException ignored) {
                // 如果定时器已经shutdown，那么返回 Long.MIN_VALUE，不再tick
                if (WORKER_STATE_UPDATER.get(HashedWheelTimer.this) == WORKER_STATE_SHUTDOWN) {
                    return Long.MIN_VALUE;
                }
            }
        }
    }

    public Set<Timeout> unprocessedTimeouts() {
        return Collections.unmodifiableSet(unprocessedTimeouts);
    }
}
```

接下来应该重点关注下怎么执行 bucket 中的任务：

```java io.netty.util.HashedWheelTimer.HashedWheelBucket
public void expireTimeouts(long deadline) {
    HashedWheelTimeout timeout = head;

    // 循环处理该桶中的所有Timeout
    while (timeout != null) {
        HashedWheelTimeout next = timeout.next;
        if (timeout.remainingRounds <= 0) { // 剩余轮次<=0，意味着本轮需要触发执行
            next = remove(timeout); // 从链中剔除
            if (timeout.deadline <= deadline) { // 已到期
                timeout.expire(); // 执行自定义定时任务
            } else {
                // 这里的代码注释也说，不可能进入到这个分支
                // The timeout was placed into a wrong slot. This should never happen.
                throw new IllegalStateException(String.format(
                        "timeout.deadline (%d) > deadline (%d)", timeout.deadline, deadline));
            }
        } else if (timeout.isCancelled()) { // 被取消则剔除
            next = remove(timeout);
        } else {
            timeout.remainingRounds --; // 轮次-1
        }
        timeout = next;
    }
}
```

```java io.netty.util.HashedWheelTimer.HashedWheelTimeout
public void expire() {
    if (!compareAndSetState(ST_INIT, ST_EXPIRED)) { // cas标记状态已过期
        return;
    }

    try {
        task.run(this); // 运行任务
    } catch (Throwable t) {
        if (logger.isWarnEnabled()) {
            logger.warn("An exception was thrown by " + TimerTask.class.getSimpleName() + '.', t);
        }
    }
}
```

到这里任务的执行流程基本也已分析完毕了，最后我们再来看下如何取消一个`Timeout`：

```java io.netty.util.HashedWheelTimer.HashedWheelTimeout
public boolean cancel() {
    // 这里仅更新状态，它将在下一个tick时从HashedWheelBucket中删除
    if (!compareAndSetState(ST_INIT, ST_CANCELLED)) { // cas标记状态已取消
        return false;
    }
    // 取消成功则加入已取消任务队列
    // If a task should be canceled we put this to another queue which will be processed on each tick.
    // So this means that we will have a GC latency of max. 1 tick duration which is good enough. This way
    // we can make again use of our MpscLinkedQueue and so minimize the locking / overhead as much as possible.
    timer.cancelledTimeouts.add(this);
    return true;
}
```

文末再提醒一句：`Worker`线程是一个 bucket 一个 bucket 顺次处理的，所以，即使有些任务执行时间超过了 100ms，“霸占”了之后好几个 bucket 的处理时间，也没关系，这些任务并不会被漏掉。但是有可能被延迟执行，毕竟工作线程是单线程。因此时间轮最适合**大量短暂定时任务**的调度处理。
