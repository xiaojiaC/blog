---
title: java并发编程的艺术
date: 2020-03-16 19:55:32
categories:
- [JAVA, 读书笔记]
tags:
- java
- concurrency
---

## 并发编程的挑战
### 上下文切换

上下文切换：CPU通过时间片分配算法来循环执行任务，当前任务执行一个时间片后会切换到下一个任务。但是，在切换前会保存上一个任务的状态，以便下次切换回这个任务时，可以再加载这个任务的状态。所以任务从保存到再加载的过程就是一次上下文切换。

<!-- more -->

{% tabs 上下文切换 %}
  <!-- tab 减少方法 -->
- 无锁并发编程
- CAS算法
- 使用最少线程
- 使用协程
  <!-- endtab -->
  <!-- tab 实践案例 -->
- 减少{% label warning@WAITTING %}线程数，因为每一次从{% label warning@WAITTING %}到{% label danger@RUNNABLE %}都会进行一次上下文的切换。
  <!-- endtab -->
  <!-- tab 分析工具 -->
`vmstat`
  <!-- endtab -->
{% endtabs %}

### 死锁

死锁：多个进程在执行过程中，因争夺同类资源且资源分配不当而造成的一种互相等待的现象，若无外力作用，它们都将永远无法继续执行，这种状态称为死锁。

{% tabs 死锁 %}
  <!-- tab 产生原因 -->
- 不可剥夺资源的竞争
> 可剥夺资源：某进程在获得该类资源时，该资源同样可以被其他进程或系统剥夺。
> 不可剥夺资源：系统把该类资源分配给某个进程时不能强制收回，只能在该进程使用完成后自动释放。
- 进程推进顺序不当
  <!-- endtab -->
  <!-- tab 必要条件 -->
- 互斥条件：一个资源每次只能被一个进程使用。
- 不剥夺条件：进程已获得的资源，在末使用完之前，不能强行剥夺。
- 请求与保持条件：一个进程因请求资源而阻塞时，对已获得的资源保持不放。
- 循环等待条件：若干进程之间形成一种头尾相接的循环等待资源关系。
  <!-- endtab -->
  <!-- tab 规避方法 -->
- 避免一个线程同时获取多个锁
- 避免一个线程在锁内同时占用多个资源，尽量保证每个锁只占用一个资源
- 尝试使用定时锁来替代使用内部锁机制
- 对于数据库锁，加锁和解锁必须在一个数据库连接里，否则会出现解锁失败的情况
- 避免对长时间的计算任务和阻塞的I/O操作加锁
  <!-- endtab -->
  <!-- tab 分析工具 -->
`jps`, `jstack $pid`
  <!-- endtab -->
{% endtabs %}

### 活锁

活锁：任务或者执行者没有被阻塞，但由于某些条件没有满足，导致一直重复尝试，失败，尝试，失败，......

规避方法:
- 引入一些随机性
- 约定重试机制避免再次冲突


### 资源限制

硬件资源限制：可以考虑使用集群并行执行程序。
软件资源限制：可以考虑使用资源池将资源复用。


## java并发机制的底层实现原理
### 基础知识

|术语|释义|
|---|----|
| 内存屏障 | 一组处理器指令，由于实现对内存操作的顺序限制。|
| 原子操作 | 不可中断的一个或一系列操作。|
| 缓存行 | 缓存中可以分配的最小存储单位。处理器填写缓存线时会加载整个缓存线，需要使用多个主内存读周期。|
| 缓存行填充 | 当处理器识别到从主存中读取的操作数是可缓存的，处理器读取整个缓存行到适当的缓存中（L1,L2,L3或所有）。|
| 缓存命中 | 如果进行高速缓存行填充操作的内存位置仍然是下次处理器访问的内存地址，处理器从缓存中读取操作数，而不是从主存中读取。|
| 写命中 | 当处理器将操作数写回到一个内存缓存的区域时，它首先会检查这个缓存的内存地址是否在缓存行中，如果存在一个有效的缓存行，则处理器将这个操作数写回到缓存，而不是写回到内存，这个操作被称为写命中。|
| 写缺失 | 一个有效的缓存行被写入到不存在的内存区域。|
| CPU流水线 | 工作方式就像工业生产中的装配流水线，在CPU中由5~6个不同功能的电路单元组成一条指令处理流水线，然后将一条x86指令拆分为5~6步再由这些电路单元分别执行，这样就能实现一个CPU时钟周期内完成一条指令，因此提高CPU的运算速度。|
| 内存顺序冲突 | 一般由假共享引起，假共享是指多个CPU同时修改同一个缓存行的不同部分而引起其中一个CPU操作无效，当出现这个内存顺序冲突时，CPU必须清空流水线。 |

### volatile

`volatile`变量修饰的共享变量进行写操作的时候会多出一个*lock前缀的指令*，该指令在多核处理器下会引发：
1. 将当前处理器缓存行的数据回写到系统内存。
2. 这个回写内存的操作会使在其他CPU里缓存了该内存地址的数据无效。

实现原理：
> 声明了volatile的变量进行写操作，JVM就会向处理器发送一条Lock前缀的指令，将这个变量所在缓存行的数据写回到系统内存。但是，就算写回到内存，如果其他处理器缓存的值还是旧的，再执行计算操作就会有问题。所以，在多处理器下，为了保证各个处理器的缓存是一致的，就会实现缓存一致性协议，每个处理器通过嗅探在总线上传播的数据来检查自己缓存的值是不是过期了，当处理器发现自己缓存行对应的内存地址被修改，就会将当前处理器的缓存行设置成无效状态，当处理器对这个数据进行修改操作的时候，会重新从系统内存中把数据读到处理器缓存里。

为什么`LinkedTransferQueue`中头、尾volatile变量追加64字节能够提高并发编程的效率呢？

大部分处理器高速缓存行是64个字节宽，且不支持部分填充缓存行。使用追加到64字节的方式来填满高速缓冲区的缓存行，避免头节点和尾节点加载到同一个缓存行，使头、尾节点在修改时不会互相锁定。

是不是在使用`volatile`变量时都应该追加到64字节呢？**并非如此**，在两种场景下不应该使用这种方式：
- 缓存行非64字节宽的处理器
- 共享变量不会被频繁地写

{% note warning %}
不过这种追加字节的方式在Java 7下可能不生效，因为Java 7变得更加智慧，它会淘汰或重新排列无用字段，需要使用其他追加字节的方式。
{% endnote %}

{% note info %}
你可能想看这里: [神奇的缓存行填充](https://blog.csdn.net/aigoogle/article/details/41517213)
{% endnote %}

### synchronized

实现原理：

> JVM基于进入和退出Monitor对象来实现方法同步和代码块同步，但两者的实现细节不一样。代码块同步是使用`monitorenter`和`monitorexit`指令实现的，而方法同步是使用另外一种方式实现的（方法修饰符上的`ACC_SYNCHRONIZED`），细节在JVM规范里并没有详细说明。但是，方法的同步同样可以使用这两个指令来实现。`monitorenter`指令是在编译后插入到同步代码块的开始位置，而`monitorexit`是插入到方法结束处和异常处，JVM要保证每个`monitorenter`必须有对应的`monitorexit`与之配对。任何对象都有一个monitor与之关联，当且一个monitor被持有后，它将处于锁定状态。线程执行到`monitorenter`指令时，将会尝试获取对象所对应的monitor的所有权，即尝试获得对象的锁。

`synchronized`用的锁是存在Java对象头里的。其存储结构如下示：

第一部分：
{% asset_img markword-32bit-vm.PNG %}
{% asset_img markword-64bit-vm.PNG %}

第二部分：
类型指针，即对象指向类元数据的指针，虚拟机通过这个指针来确定对象是哪个类的实例。但并不是所有虚拟机实现都需要在对象头上保持类型指针。因为有的虚拟机使用*句柄*进行对象访问定位，而不是*直接指针*访问。

第三部分：
如果对象是一个java数组，那么在对象头中还必须有一块用于记录数组长度的数据。可能是对齐填充，并不是必要存在的，也没有特别含义，仅起占位符的作用。

#### 锁

在Java SE 1.6中，锁一共有4种状态，级别从低到高依次是：**无锁状态**、**偏向锁状态**、**轻量级锁状态**和**重量级锁**状态，这几个状态会随着竞争情况逐渐升级。锁可以升级但不能降级。

{% asset_img synchonized.png %}

### 原子操作

原子操作：不可被中断的一个或一系列操作。

处理器如何实现原子操作：
- 通过总线锁保证原子性（总线上声明`lock#`信号）
- 通过缓存锁定来保证原子性（修改内部的内存地址+缓存一致性机制使*单个*缓存行无效）

Java如何实现原子操作：
- 使用循环CAS
    - ABA问题：解决方法追加版本号，可参考`AtomicStampedReference`
    - 循环时间长开销大
    - 只能保证一个共享变量的原子操作：解决方法使用锁替换或把多个共享变量合并成一个共享变量来操作，可参考`AtomicReference`
- 使用锁机制


## java内存模型
### 基础知识

命令式编程中，线程之间的通信机制有两种：**共享内存**和**消息传递**。

从源代码到指令序列可能发生哪些重排序？
- 编译器优化的重排序：编译器在不改变单线程程序语义的前提下，可以重新安排语句的执行顺序。
- 指令级并行的重排序：如果不存在数据依赖性，处理器可以改变语句对应机器指令的执行顺序。
> 如果两个操作访问*同一个变量*，且这两个操作中*有一个为写操作*，此时这两个操作之间就存在数据依赖性。
- 内存系统的重排序：由于处理器使用缓存和读/写缓冲区，这使得加载和存储操作看上去可能是在乱序执行。

{% asset_img code-to-instruction-reorder.PNG 源代码到指令序列的重排序 %}

Java线程之间的通信由*Java内存模型*控制，JMM决定一个线程对共享变量的写入何时对另一个线程可见。确保在不同的编译器和不同的处理器平台之上，为程序员提供一致的内存可见性保证。

对于编译器重排序，JMM的编译器重排序规则会禁止特定类型的编译器重排序（不是所有的编译器重排序都要禁止）。
对于处理器重排序，JMM的处理器重排序规则会要求Java编译器在生成指令序列时，插入内存屏障指令来禁止特定类型的处理器重排序。

{% note info %}
常见的处理器（基本都有写缓冲区）都允许Store-Load重排序；都不允许对存在数据依赖的操作做重排序。
{% endnote %}

### as-if-serial语义

as-if-serial语义：不管怎么重排序（编译器和处理器为了提高并行度），（单线程）程序的执行结果不能被改变。编译器、runtime和处理器都必须遵守as-if-serial语义。

### 顺序一致性内存模型

顺序一致性内存模型有哪些特性？

- 一个线程中的所有操作必须按照程序的顺序串行执行。
- （不管程序是否同步）所有线程都只能看到一个单一的操作执行顺序。在顺序一致性内存模型中，每个操作都必须原子执行且立刻对所有线程可见。

在JMM中，临界区内的代码可以重排序（但JMM不允许临界区内的代码“逸出”到临界区之外，那样会破坏监视器的语义）。
JMM不保证对64位的long型和double型变量的写操作具有原子性。

### volatile的内存语义

理解volatile特性的一个好方法是：把对volatile变量的单个读/写，看成是使用**同一个锁**对这些**单个**读/写操作做了同步。

这意味着，1. 对一个volatile变量的读，总是能看到（任意线程）对这个volatile变量最后的写入。2. 即使是64位的long型和double型变量，只要它是volatile变量，对该变量的单个读/写就具有原子性。

内存屏障：

硬件层的内存屏障分为两种：`Load Barrier` 和 `Store Barrier` 即读屏障和写屏障。

{% tabs 内存屏障 %}
  <!-- tab 作用 -->
1. 阻止屏障两侧的指令重排序；
2. 强制把写缓冲区/高速缓存中的脏数据等写回主内存，让缓存中相应的数据失效（必须从主内存从新加载）。
  <!-- endtab -->
  <!-- tab 分类 -->
- 对于`Load Barrier`来说，在指令前插入`Load Barrier`，可以让高速缓存中的数据失效，强制从新从主内存加载数据；
- 对于`Store Barrier`来说，在指令后插入`Store Barrier`，能让写入缓存中的最新数据更新写入主内存，让其他线程可见。
  <!-- endtab -->
  <!-- tab java中的分类 -->
{% asset_img java-memory-barrier.PNG %}
  <!-- endtab -->
{% endtabs %}

volatile的编译器重排序规则：
- 当第一个操作是volatile写，第二个操作是volatile读时，不能重排序。
- 当第一个操作是volatile读时，不管第二个操作是什么，都不能重排序。
- 当第二个操作是volatile写时，不管第一个操作是什么，都不能重排序。

volatile的处理器内存屏障插入策略：
- 在每个volatile写操作的前面插入一个`StoreStore`屏障。
- 在每个volatile写操作的后面插入一个`StoreLoad`屏障。
- 在每个volatile读操作的后面插入一个`LoadLoad`屏障。
- 在每个volatile读操作的后面插入一个`LoadStore`屏障。

{% note %}
我的疑惑：为什么不需要在每个volatile写操作的前面插入一个LoadStore屏障，来防止第一个普通读和第二个volatile写操作重排序？？？
{% endnote %}

### 锁的内存语义

在`ReentrantLock`中，调用`lock()`方法获取锁；调用`unlock()`方法释放锁。

加锁方法首先读volatile变量`state`，在释放锁的最后写volatile变量`state`。根据volatile的happens-before规则，释放锁的线程在写volatile变量之前可见的共享变量，在获取锁的线程读取同一个volatile变量后将立即变得对获取锁的线程可见。

获取锁中的CAS又如何同时具有volatile读和volatile写的内存语义？

从编译器角度：
编译器不会对volatile读与volatile读后面的任意内存操作重排序；编译器不会对volatile写与volatile写前面的任意内存操作重排序。组合这两个条件，意味着为了同时实现volatile读和volatile写的内存语义，编译器不能对CAS与CAS前面和后面的任意内存操作重排序。

从处理器角度：
在常见的intel X86处理器中，源码中会根据当前处理器的类型来决定是否为`cmpxchg`指令添加`lock`前缀。lock前缀的第2点和第3点所具有的内存屏障效果，足以同时实现volatile读和volatile写的内存语义。
> intel的手册对lock前缀的说明: 1. 确保对内存的读-改-写操作原子执行。2. 禁止该指令，与之前和之后的读和写指令重排序。3. 把写缓冲区中的所有数据刷新到内存中。

综上述，可见`ReentrantLock`内存语义实现利用了volatile变量的写-读所具有的内存语义和CAS所附带的volatile读和volatile写的内存语义。

### final域的内存语义

final域的编译器重排序规则：
- 在构造函数内对一个final域/final域引用的对象成员域的写入，与随后把这个被构造对象的引用赋值给一个引用变量，这两个操作之间不能重排序。
- 初次读一个包含final域的对象的引用，与随后初次读这个final域，这两个操作之间不能重排序。

final域的处理器内存屏障插入策略：
- 编译器会在final域的写之后，构造函数return之前，插入一个`StoreStore`屏障。禁止处理器把final域的写重排序到构造函数之外。
- 编译器会在读final域操作的前面插入一个`LoadLoad`屏障。禁止处理器把存在间接依赖关系的操作做重排序。

final域为引用类型时，若多个线程同时访问其内的可变状态变量，仍需要使用同步原语（lock或volatile）来确保内存可见性。

{% note danger %}
`final`引用不能从构造函数内“逸出”。
{% endnote %}

### happens-before

happens-before定义：

JMM对程序员的{% label danger@承诺 %}：如果一个操作happens-before另一个操作，那么第一个操作的执行结果将对第二个操作可见，而且第一个操作的执行顺序排在第二个操作之前。

JMM对编译器和处理器重排序的约束原则：两个操作之间存在happens-before关系，<u>并不意味着Java平台的具体实现必须要按照happens-before关系指定的顺序来执行</u>。如果重排序之后的执行结果，与按happens-before关系来执行的结果一致，那么这种重排序并不非法（即JMM允许这种重排序）。

happens-before规则：

- 程序顺序规则：一个线程中的每个操作，happens-before于该线程中的任意后续操作。
- 监视器锁规则：对一个锁的解锁，happens-before于随后对这个锁的加锁。
- volatile变量规则：对一个volatile域的写，happens-before于任意后续对这个volatile域的读。
- `start()`规则：如果线程A执行操作`ThreadB.start()`（启动线程B），那么A线程的`ThreadB.start()`操作happens-before于线程B中的任意操作。
- `join()`规则：如果线程A执行操作`ThreadB.join()`并成功返回，那么线程B中的任意操作happens-before于线程A从`ThreadB.join()`操作成功返回。
- 中断法则：一个线程调用另一个线程的`interrupt()` happens-before于被中断的线程发现中断。
- 终结法则：一个对象的构造函数的结束happens-before于这个对象finalizer的开始。
- 传递性规则：如果A happens-before B，且B happens-before C，那么A happens-before C。

{% btn #as-if-serial语义, as-if-serial语义 %}保证单线程内程序的执行结果不被改变，{% btn #happens-before, happens-before关系 %}保证正确同步的多线程程序的执行结果不被改变。

## java并发编程的基础
### 线程

#### 线程优先级

{% note danger %}
线程优先级不能作为程序正确性的依赖，因为操作系统可以完全不用理会Java线程对于优先级的设定。
{% endnote %}

#### 线程状态

| [线程状态](https://docs.oracle.com/javase/7/docs/api/java/lang/Thread.State.html) | 含义 | 诱发动作 |
|---|----|-----|
| NEW | 新建线程对象，但尚未启动（`start()`） | `new Thread()`
| RUNNABLE | 一个可运行的线程，包含就绪（等待系统调度分配cpu时间片）和运行中（获得cpu时间片开始运行）两种状态。 | Ready: `Thread.yield()`, Running: 被线程调度器选择
| BLOCKED | 被阻塞等待监视器锁。 | IO阻塞, 等待进入同步代码块或方法
| WAITING | 无限期等待另一个线程执行一个特定操作（通知或中断）。 | `Object.wait()`, `Thread.join()`, `LockSupport.park()`
| TIMED_WAITING | 具有指定等待时间，可以在指定的时间内自行返回。 | `Thread.sleep(long)`,  `Object.wait(long timeout)`,  `Thread.join(long timeout)`,  `LockSupport.parkNanos(Object blocker, long nanos)`, `LockSupport.parkUntil(Object blocker, long deadline)`
| TERMINATED | 线程已经执行完毕。 | `run()`退出, `Thread.stop()`, 线程中断退出,  阻塞IO被关闭

{% asset_img thread-state-transition.png 线程状态变迁图 %}

#### Daemon线程

可以通过调用`Thread.setDaemon(true)`将线程设置为Daemon线程，<u>但需要在启动线程之前设置</u>。

当Java虚拟机中不存在非Daemon线程时，虚拟机将会退出。Java虚拟机中的所有Daemon线程都需要立即终止。因此在构建Daemon线程时，<u>不能依靠finally块中的内容来确保执行关闭或清理资源的逻辑</u>。

#### API

`thread.start()`：启动线程。启动一个线程前，{% label primary@最好为这个线程设置线程名称 %}，因为这样便于使用jstack分析程序或者进行问题排查。
`thread.isInterrupted()`：判断线程是否被中断。
  - 如果线程已经处于终结状态，即使被中断过，在调用该线程对象的`isInterrupted()`时依旧会返回false。
  - 从Java的API中可以看到，许多声明抛出`InterruptedException`的方法（例如：`Thread.sleep(long millis)`方法）在抛出`InterruptedException`之前，Java虚拟机会先将该线程的中断标识位清除，然后抛出`InterruptedException`，此时调用`isInterrupted()`方法将会返回false。

`Thread.interrupted()`：对当前线程的中断标识位进行复位。
~~`thread.suspend()`~~：在调用后，线程不会释放已经占有的资源（比如锁），而是占有着资源进入睡眠状态，这样容易引发死锁问题。
~~`thread.stop()`~~：在终结一个线程时不会保证线程的资源正常释放，通常是没有给予线程完成资源释放工作的机会，因此会导致程序可能工作在不确定状态下。
~~`thread.sleep()`~~：也是占有着资源进入睡眠状态，而`Object.wait()`则相反。
`thread.yield()`：使当前线程从执行状态（运行状态）变为可执行态（就绪状态）。cpu调度器会从众多的可执行态里选择，也就是说，当前也就是刚刚的那个线程还是有可能会被再次执行到的，并不是说一定会执行其他线程而该线程在下一次中不会执行到了。
threadA执行`threadB.join()`：当前线程A等待线程B终止之后才从`threadB.join()`返回。原理利用了等待/通知机制，threadB终止之后会调用线程自身的`notifyAll()`方法，通知所有等待在该线程对象上的线程。

#### 等待/通知机制

1. 使用`wait()`、`notify()`和`notifyAll()`时需要先对调用对象加锁。
2. 调用`wait()`方法后，线程状态由`RUNNING`变为`WAITING`，并将当前线程放置到对象的**等待队列**。
3. `notify()`或`notifyAll()`方法调用后，等待线程依旧不会从`wait()`返回，需要调用`notify()`或
`notifAll()`的线程释放锁之后，等待线程才有机会从`wait()`返回。
4. `notify()`方法将等待队列中的一个等待线程从**等待队列**中移到**同步队列**中，而`notifyAll()`方法则是将等待队列中所有的线程全部移到同步队列，被移动的线程状态由`WAITING`变为`BLOCKED`。
5. 从`wait()`方法返回的前提是获得了调用对象的锁。

等待/通知的经典范式：

```java
    synchronized (对象) {
        while (条件不满足) {
            对象.wait();
        }
        对应的处理逻辑
    }

    synchronized (对象) {
        改变条件
        对象.notifyAll();
    }
```

#### 管道输入/输出流

管道输入/输出流主要用于线程之间的数据传输，而传输的媒介为内存。

对于Piped类型的流，必须先要进行绑定，也就是调用`connect()`方法，如果没有将输入/输出流绑定起来，对于该流的访问将会抛出异常。

## java中的锁

锁的经典范式：

```java
    Lock lock = new ReentrantLock();
    lock.lock();
    try {
        对应的处理逻辑
    } finally {
        lock.unlock();
    }
```

在finally块中释放锁，目的是保证在获取到锁之后，最终能够被释放。{% label danger@不要 %}将获取锁的过程写在try块中，因为如果在获取锁（自定义锁的实现）时发生了异常，异常抛出的同时，也会导致莫名的锁释放。


### 显示锁和隐式锁的区别

synchronized | [Lock](https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/locks/Lock.html)
-----|--------
关键字，隐式获取/释放锁 | 接口，显式获取/释放锁
代码简单，被大多程序员广泛使用，默认推荐　| 代码稍复杂，在try块外获取锁，在finally块中释放锁，迫于性能调优时再用
 - | 可尝试非阻塞获取锁（线程尝试获取锁，若锁未被其他线程持有，则成功获取并持有锁）
-  | 可中断获取锁（获取到锁的线程能够响应中断，当该线程被中断时，中断异常将被抛出，同时锁释放）
 - | 可超时获取锁（在指定的截止时间之前获取锁，若超时仍无法获取锁，则返回）


锁是**面向使用者**的，它定义了使用者与锁交互的接口(比如可以允许两个线程并行访问),隐藏了实现细节; 
同步器**面向锁的实现者**,它简化了锁的实现方式，屏蔽了同步状态管理、线程的排队、等待与唤醒等底层操作。

{% asset_img concurrent-pkg-impl.png concurrent包的实现示意图 %}

### 同步器可重写的方法

方法 | 描述
----------|--------
`boolean tryAcquire(int arg)` | 独占式获取同步状态。实现该方法需要查询当前同步状态并判断是否符合预期，然后再进行CAS设置同步状态。
`boolean tryRelease(int arg)` | 独占式释放同步状态。等待获取同步状态的线程将有机会获取同步状态。
`int tryAcquireShared(int arg)` | 共享式获取同步状态。返回大于等于0的值表示获取成功，否则获取失败。
`boolean tryReleaseShared(int arg)` | 共享式释放同步状态。
`boolean isHeldExclusively()` | 同步状态是否在独占模式下被线程占用。

### 同步器提供的便捷方法

方法 | 描述
----------|--------
`void acquire(int arg)` | 独占式获取同步状态，如果当前线程获取同步状态成功，则由该方法返回。否则，将会进入同步队列等待，该方法**忽略中断**。
`void acquireInterruptibly(int arg) throws InterruptedException` | 同上，但该方法响应中断，在同步队列中等待的线程可以被中断，会抛出InterruptedException并返回。
`boolean tryAcquireNanos(int arg, long nanosTimeout) throws InterruptedException` | 同上且增加了超时限制，如果在超时时间内没有获取到同步状态将返回false，否则返回true。
`boolean release(int arg)` | 独占式释放同步状态。释放后会唤醒同步队列中的第一个节点所包含的线程。
`void acquireShared(int arg)` | 共享式获取同步状态，若同步未获取获取成功则会进入同步队列等待。与独占式获取主要区别在**同一时刻可以有多个线程**获取同步状态。
`void acquireSharedInterruptibly(int arg) throws InterruptedException` |同上，但该方法响应中断
`boolean tryAcquireSharedNanos(int arg, long nanosTimeout) throws InterruptedException` | 同上且增加了超时限制
`boolean releaseShared(int arg)` | 共享式释放同步状态。

### 同步器中节点的含义

[AQS](https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/locks/AbstractQueuedSynchronizer.html)#Node的属性 | 含义
---------|-------
`int waitStatus` | 状态字段，仅可能取以下几种值：状态字段，仅可能取以下几种值：<br/><br/>`0`: 初始化状态。<br/>`CANCELLED(1)`: 由于取消或中断，节点取消获取同步状态，节点进入该状态后将不会再发生变化。注意取消节点的线程永远不会再阻塞。<br/>`SIGNAL(-1)`: 当前节点的后继节点是(或不久的将来)阻塞的(通过park)，因此当前节点释放或取消同步状态时必须通知(通过unpark)后继节点，为了避免竞争激烈，acquire方法必须首先表明他们需要一个启动信号，然后原子性重试获取同步状态，最后在失败时阻塞。<br/>`CONDITION(-2)`: 此节点当前处于条件队列中。直到被转移(signal/signalAll)才会被加入到同步队列中，转移后状态将被设置为0。<br/>`PROPAGATE(-3)`: releaseShared应该传播给其他节点。在doReleaseShared中设置（仅限头节点）以确保继续传播，即使其他操作已经介入。
`Node prev` | 前驱节点，当节点加入到同步队列时被设置（CAS尾部加入）
`Node next` | 后继节点
`Thread thread` | 获取同步状态的线程
`Node nextWaiter` | 条件队列中的后继节点，或特殊值`SHARED`。因为条件队列只有在保持独占模式时才被访问，所以我们只需要一个简单的链接队列来在节点等待条件时保存节点。然后将它们转移到同步队列中以重新获取同步状态。并且因为condition只能是独占的，所以我们通过使用SHARED特殊值来指示共享模式。

### Object的监视器方法与Condition接口对比

对比项 | Object监视器方法 | [Condition](https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/locks/Condition.html)
---|---|----
前置条件 | 获取对象的监视器锁 | 调用`Lock.lock()`获取锁<br/> 调用`Lock.newCondition()`获取`Condition`对象
调用方法 | 直接调用，如：`object.wait()` | 直接调用，如：`condition.await()`
等待队列个数 | 一个 | 多个
当前线程释放锁并进入等待队列 | 支持 | 支持
当前线程释放锁并进入等待队列，在等待状态中*不*响应中断 | 不支持 | 支持
当前线程释放锁并进入超时等待状态 | 支持 | 支持
当前线程释放锁并进入等待状态到将来的某个时间 | 不支持 | 支持
唤醒等待队列中的一个线程 | 支持 | 支持
唤醒等待队列中的全部线程 | 支持 | 支持

{% asset_img sync-and-wait-queue.png 同步队列和等待队列的模样 %}

### 通过源码看世界
#### AQS超时获取锁的源代码

```java
    // acquire，acquireInterruptibly与此大同小异
    public final boolean tryAcquireNanos(int arg, long nanosTimeout)
            throws InterruptedException {
        if (Thread.interrupted()) 
            throw new InterruptedException();
        return tryAcquire(arg) || // 先尝试获取一次
            doAcquireNanos(arg, nanosTimeout); // 尝试失败，将其包装成Node，放入等待队列，并等待前驱节点唤醒
    }

    private boolean doAcquireNanos(int arg, long nanosTimeout)
            throws InterruptedException {
        if (nanosTimeout <= 0L)
            return false;
        final long deadline = System.nanoTime() + nanosTimeout;
        final Node node = addWaiter(Node.EXCLUSIVE); // 包装成独占模式等待者
        boolean failed = true;
        try {
            for (;;) {
                final Node p = node.predecessor();
                if (p == head && tryAcquire(arg)) { // 若是头节点，尝试获取同步状态，成功则将自己设置成头节点
                    setHead(node);
                    p.next = null; // 释放前驱节点引用，便于GC回收原头节点
                    failed = false;
                    return true;
                }
                nanosTimeout = deadline - System.nanoTime();
                if (nanosTimeout <= 0L) // 超时仍未获取到，则返回fasle
                    return false;
                if (shouldParkAfterFailedAcquire(p, node) && // 如果前驱节点状态(SIGNAL)正常，则等待；若已取消(CANCELLED)为其寻找一个正常的前驱节点；否则CAS设置前驱节点状态为正常态
                    nanosTimeout > spinForTimeoutThreshold) // 超时时间大于阈值，则使用parkNanos超时等待；否则采用高速自旋重试
                    LockSupport.parkNanos(this, nanosTimeout);
                if (Thread.interrupted()) // 被唤醒发现线程中断，则抛出中断异常
                    throw new InterruptedException();
            }
        } finally {
            if (failed) 
                cancelAcquire(node); // 超时或中断退出时，则取消获取同步状态
        }
    }
```

{% asset_img aqs-doAcquireNanos.png AQS超时获取锁的流程图 %}

#### AQS释放锁的源代码

```java
    public final boolean release(int arg) {
        if (tryRelease(arg)) { // 尝试释放同步状态
            Node h = head;
            if (h != null && h.waitStatus != 0)
                unparkSuccessor(h); // 释放成功，唤醒头节点的后继节点
            return true;
        }
        return false;
    }

    private void unparkSuccessor(Node node) {
        int ws = node.waitStatus;
        if (ws < 0) 
            compareAndSetWaitStatus(node, ws, 0);　// 将头节点状态修改为0

        Node s = node.next;
        if (s == null || s.waitStatus > 0) { // 头节点不存在后继节点或后继节点已取消获取同步状态
            s = null;　
            // 从前往后寻找不一定能找到刚刚加入队列的后继节点, 因为在Node addWaiter(Node mode)中，是先CAS设置尾节点，再设置前驱节点和尾节点的引用关系
            for (Node t = tail; t != null && t != node; t = t.prev) 
                if (t.waitStatus <= 0) // 从队尾往前找，找到第一个需要唤醒的节点
                    s = t;
        }
        if (s != null)
            LockSupport.unpark(s.thread); // 唤醒线程
    }
```

#### ReentrantLock非公平获取锁源代码

```java
    // NonfairSync类中
    final void lock() {
        if (compareAndSetState(0, 1)) // 非公平锁直接尝试获取锁
            setExclusiveOwnerThread(Thread.currentThread());
        else
            acquire(1);
    }

    // Sync父类中
    final boolean nonfairTryAcquire(int acquires) {
        final Thread current = Thread.currentThread();
        int c = getState();
        if (c == 0) { // 目前没有其他线程获得锁，当前线程就可以尝试获取锁
            if (compareAndSetState(0, acquires)) { // CAS修改同步状态
                setExclusiveOwnerThread(current);
                return true;
            }
        }
        else if (current == getExclusiveOwnerThread()) { // 当前线程持有锁，支持重入
            int nextc = c + acquires;
            if (nextc < 0) // overflow
                throw new Error("Maximum lock count exceeded");
            setState(nextc); // 已持有锁，可直接修改
            return true;
        }
        return false; // 修改失败返回false
    }
```

#### ReentrantLock公平获取锁源代码

```java
    // FairSync类中
    final void lock() {
        acquire(1);
    }

    protected final boolean tryAcquire(int acquires) {
        final Thread current = Thread.currentThread();
        int c = getState();
        if (c == 0) {
            if (!hasQueuedPredecessors() && // 多了这个判断，需要判断队列中是否还有前驱节点线程
                compareAndSetState(0, acquires)) {
                setExclusiveOwnerThread(current);
                return true;
            }
        }
        else if (current == getExclusiveOwnerThread()) {
            int nextc = c + acquires;
            if (nextc < 0)
                throw new Error("Maximum lock count exceeded");
            setState(nextc);
            return true;
        }
        return false;
    }
```

#### ReentrantLock释放锁的源代码

```java
    protected final boolean tryRelease(int releases) {
        int c = getState() - releases;
        if (Thread.currentThread() != getExclusiveOwnerThread()) // 当前线程未持有锁，不可释放
            throw new IllegalMonitorStateException();
        boolean free = false;
        if (c == 0) { // 由于锁可重入，当同步状态等于0时，才代表真正释放掉
            free = true;
            setExclusiveOwnerThread(null);
        }
        setState(c);
        return free;
    }
```

#### ReentrantReadWriteLock获取释放锁源代码

```java
    /*以高16位表示所有线程获取读锁数，以低16位表示单个线程获取写锁数 */
    
    static final int SHARED_SHIFT   = 16;
    static final int SHARED_UNIT    = (1 << SHARED_SHIFT); // 0x00010000
    static final int EXCLUSIVE_MASK = (1 << SHARED_SHIFT) - 1; // 低16位全为1

    static int sharedCount(int c)    { return c >>> SHARED_SHIFT; } // 根据同步状态计算已持有的读锁数
    static int exclusiveCount(int c) { return c & EXCLUSIVE_MASK; } // 根据同步状态计算已持有的写锁数
    
    protected final boolean tryAcquire(int acquires) { // 获取独占锁（写锁）
        Thread current = Thread.currentThread();
        int c = getState();
        int w = exclusiveCount(c); // 持有的写锁数
        if (c != 0) { 
            // (Note: if c != 0 and w == 0 then shared count != 0)
            // 如果同步状态不为0但是写锁数为0,代表持有读锁(不为0)
            if (w == 0 || current != getExclusiveOwnerThread()) // 已持有读锁或不是当前线程持有写锁，均不可再获取写锁
                return false;
            if (w + exclusiveCount(acquires) > MAX_COUNT) // 获取写锁数超限
                throw new Error("Maximum lock count exceeded");
            setState(c + acquires); // 是当前线程持有写锁，可重入获取
            return true;
        }
        if (writerShouldBlock() || // 公平模式下需要判断同步队列中是否有前驱节点在等待
            !compareAndSetState(c, c + acquires)) // 无线程获取写锁，CAS获取锁
            return false;
        setExclusiveOwnerThread(current); // 获取成功
        return true;
    }

    protected final boolean tryRelease(int releases) {
        if (!isHeldExclusively()) // 非持有写锁的线程不可释放写锁
            throw new IllegalMonitorStateException();
        int nextc = getState() - releases;
        boolean free = exclusiveCount(nextc) == 0; // 因为可重入，当同步状态低16位全为0，才代表成功释放
        if (free)
            setExclusiveOwnerThread(null);
        setState(nextc); 
        return free;
    }

    protected final int tryAcquireShared(int unused) { // 获取共享锁(读锁)
        Thread current = Thread.currentThread();
        int c = getState();
        if (exclusiveCount(c) != 0 &&
            getExclusiveOwnerThread() != current)　// 写锁已被持有但不是当前线程，获取读锁阻塞
            return -1;
        int r = sharedCount(c);　// 持有的读锁数
        if (!readerShouldBlock() && // 公平模式下需要判断同步队列中是否有前驱节点在等待
            r < MAX_COUNT &&
            compareAndSetState(c, c + SHARED_UNIT)) { // 无线程持有写锁，所有线程都可获取读锁
            if (r == 0) { // 无线程持有读锁，标记当前线程首次获取读锁1次
                firstReader = current;
                firstReaderHoldCount = 1;
            } else if (firstReader == current) { // 有线程持有读锁，若当前线程是首次获取读锁的线程，则增加读锁持有数
                firstReaderHoldCount++;
            } else { // 有线程持有读锁，但不是首次获取读锁的线程，则初始化线程相应读锁持有数
                HoldCounter rh = cachedHoldCounter;
                if (rh == null || rh.tid != getThreadId(current)) // 无缓存或缓存的计数不是当前线程
                    cachedHoldCounter = rh = readHolds.get(); // 获取线程本地缓存
                else if (rh.count == 0)  // 有缓存且当前线程第一次获取锁，则初始化线程(锁计数)本地缓存
                    readHolds.set(rh);
                rh.count++; // 当前线程持有读锁数加1
            }
            return 1;
        }
        return fullTryAcquireShared(current); // 自旋获取读锁，用于应对首次尝试CAS未命中和重入读锁的情况
    }

    protected final boolean tryReleaseShared(int unused) {
        Thread current = Thread.currentThread();
        if (firstReader == current) { // 当前线程是第一个获取读锁的线程
            // assert firstReaderHoldCount > 0;
            if (firstReaderHoldCount == 1) // 线程仅持有1个读锁，释放后即无第一个读线程
                firstReader = null;
            else
                firstReaderHoldCount--; 
        } else {
            HoldCounter rh = cachedHoldCounter;
            if (rh == null || rh.tid != getThreadId(current))
                rh = readHolds.get();
            int count = rh.count;
            if (count <= 1) { // 只获取一次读锁，则直接移除，
                readHolds.remove();
                if (count <= 0)
                    throw unmatchedUnlockException();
            }
            --rh.count; // 减少缓存计数信息
        }
        for (;;) { // 自旋释放读锁
            int c = getState();
            int nextc = c - SHARED_UNIT;
            if (compareAndSetState(c, nextc))
                // Releasing the read lock has no effect on readers,
                // but it may allow waiting writers to proceed if
                // both read and write locks are now free.
                return nextc == 0;
        }
    }
```

## java中的阻塞队列

插入和移除操作的4种处理方式：

方法/处理方式 | 抛出异常 | 返回特殊值 | 一直阻塞 | 超时退出
---|---|---|---|----
插入方法 | `add(e)` | `offer(e)` | `put(e)` | `offer(e, time, unit)`
移除方法 | `remove()` | `poll()` | `take()` | `poll(time, unit)`
检查方法 | `element()` | `peek()` | 不可用 | 不可用

提供了哪些阻塞队列？
- `ArrayBlockingQueue`：由数组结构组成的有界阻塞队列。
- `LinkedBlockingQueue`：由链表结构组成的有界阻塞队列。
- `PriorityBlockingQueue`：支持优先级排序的无界阻塞队列。
- `DelayQueue`：使用优先级队列实现的无界阻塞延时队列。（延迟队列中的元素到了延迟时间则可以从中取出，否则无法取出）
- `SynchronousQueue`：不存储元素的阻塞队列。
- `LinkedTransferQueue`：由链表结构组成的无界阻塞队列。
- `LinkedBlockingDeque`：由链表结构组成的双向阻塞队列。

## java中的原子操作类

- `AtomicBoolean`：原子更新布尔类型。
- `AtomicInteger`：原子更新整型。
- `AtomicLong`：原子更新长整型。
- `AtomicIntegerArray`：原子更新整型数组里的元素。（对内部的数组元素(将传入数组复制一份)进行修改，不会影响传入的数组）
- `AtomicLongArray`：原子更新长整型数组里的元素。
- `AtomicReferenceArray`：原子更新引用类型数组里的元素。
- `AtomicReference`：原子更新引用类型。
- `AtomicIntegerFieldUpdater`：原子更新整型字段的更新器。
- `AtomicLongFieldUpdater`：原子更新长整型字段的更新器。
- `AtomicReferenceFieldUpdater`：原子更新引用类型字段的更新器。
- `AtomicMarkableReference`：原子更新带有boolean标记位的引用类型。
- `AtomicStampedReference`：原子更新带有版本号的引用类型。

## java中的并发工具类

- `CountDownLatch`（倒计数器）：一个或多个线程等待其他线程完成操作。{% label info@只能使用一次 %}
- `CyclicBarrier`（循环屏障）：让一组线程到达一个屏障（也可以叫同步点）时被阻塞，直到最后一个线程到达屏障时，屏障才会开门，所有被屏障拦截的线程才会继续运行。{% label info@可以使用reset()方法重置，多次使用 %}
- `Semaphore`（信号量）：控制同时访问特定资源的线程数量。
- `Exchanger`（交换者）：用于进行线程间的数据交换。它提供一个同步点，在这个同步点，两个线程可以交换彼此的数据。
- Guava `RateLimiter`（限流器）：使用漏桶算法（利用一个缓存区，请求进入系统时，无论请求的速率如何都先保存在缓存区内，然后以固定的流速流出缓存区进行处理）或令牌桶算法（桶中存放的不再是请求，而是令牌，处理程序只有拿到令牌后才能对请求进行处理，无令牌时程序要么等待令牌，要么丢弃请求，为了限制流速，会在每个单位时间产生一定量的令牌放入桶中）对请求进行限流。

## java中的线程池

{% asset_img thread-pool-processing.png %}

1. 如果当前运行的线程少于`corePoolSize`，则创建新线程来执行任务（{% label danger@注意：执行这一步骤需要获取全局锁 %}）。
2. 如果运行的线程等于或多于`corePoolSize`，则将任务加入`BlockingQueue`。
3. 如果无法将任务加入`BlockingQueue`（队列已满），则创建新的线程来处理任务（{% label danger@注意：执行这一步骤需要获取全局锁 %}）。
4. 如果创建新线程将使当前运行的线程超出`maximumPoolSize`，任务将被拒绝，并调用`RejectedExecutionHandler.rejectedExecution()`方法。

### API

#### ThreadPoolExecutor
```java
public ThreadPoolExecutor(int corePoolSize, // 核心线程数
                          int maximumPoolSize, // 最大线程数
                          long keepAliveTime, // 线程数量超过核心线程时，多余的空闲线程的最大存活时间
                          TimeUnit unit, // 时间的单位
                          BlockingQueue<Runnable> workQueue, // 阻塞队列，暂存被提交但尚未执行的任务
                          ThreadFactory threadFactory, // 创建工作线程的工厂
                          RejectedExecutionHandler handler) { // 拒绝策略，任务太多来不及处理时如何拒绝
    ...
}
```

`BlockingQueue`（阻塞队列）：
- `ArrayBlockingQueue`：是一个基于数组结构的有界阻塞队列，此队列按FIFO（先进先出）原则对元素进行排序。
- `LinkedBlockingQueue`：一个基于链表结构的阻塞队列，此队列按FIFO（先进先出）排序元素，吞吐量通常要高于`ArrayBlockingQueue`。
- `SynchronousQueue`：一个不存储元素的阻塞队列。每个插入操作必须等到另一个线程调用移除操作，否则插入操作一直处于阻塞状态，吞吐量通常要高于`LinkedBlockingQueue`。
- `PriorityBlockingQueue`：一个具有优先级的无限阻塞队列。

`RejectedExecutionHandler`（饱和策略）：
- `AbortPolicy`：直接抛出异常。
- `CallerRunsPolicy`：只用调用者所在线程来运行任务。
- `DiscardOldestPolicy`：丢弃队列里最老的一个任务，并执行当前任务。
- `DiscardPolicy`：不处理，丢弃掉。

#### 向线程池提交任务
- `execute()`：用于提交不需要返回值的任务，所以无法判断任务是否被线程池执行成功。
- `submit()`：用于提交需要返回值的任务。

#### 关闭线程池
- `shutdown()`：只是将线程池的状态设置成`SHUTDOWN`状态，然后中断所有没有正在执行任务的线程。
- `shutdownNow()`：首先将线程池的状态设置成`STOP`，然后尝试停止所有的正在执行或暂停任务的线程，并返回等待执行任务的列表。

### 合理配置线程池

线程数配置：
- 按任务的性质拆分：
<u>CPU密集型任务</u>应配置尽可能小的线程，如配置`Ncpu+1`个线程的线程池。由于<u>IO密集型任务</u>线程并不是一直在执行任务，则应配置尽可能多的线程，如`2*Ncpu`。<u>混合型的任务</u>，如果可以拆分，将其拆分成一个CPU密集型任务和一个IO密集型任务，只要这两个任务执行的时间相差不是太大，那么分解后执行的吞吐量将高于串行执行的吞吐量。如果这两个任务执行时间相差太大，则没必要进行分解。可以通过`Runtime.getRuntime().availableProcessors()`方法获得当前设备的CPU个数。

- 按任务优先级拆分：
优先级不同的任务可以使用优先级队列`PriorityBlockingQueue`来处理。它可以让优先级高的任务先执行。但需要注意如果一直有优先级高的任务提交到队列里，那么优先级低的任务可能永远不能执行。

- 按任务执行时间拆分：
执行时间不同的任务可以交给不同规模的线程池来处理，或者可以使用优先级队列，让执行时间短的任务先执行。

- 按任务的依赖性拆分:
依赖数据库连接池的任务，因为线程提交SQL后需要等待数据库返回结果，等待的时间越长，则CPU空闲时间就越长，那么线程数应该设置得越大，这样才能更好地利用CPU。

```
    Ncpu = cpu的数量
    Ucpu = 目标cpu的使用率，0 ≤ Ucpu ≤ 1
    W/C = 等待时间与计算时间的比率
    为保持处理器达到期望的使用率，最优的线程池大小等于：Nthreads = Ncpu * Ucpu * (1 + W/C)
```

队列配置：
- {% label primary@建议使用有界队列 %}
- 吞吐量比较：
`SynchronousQueue(Executors.newCachedThreadPool)`>`LinkedBlockingQueue(Executors.newFixedThreadPool())`>`ArrayBlockingQueue`

拒绝策略配置：
- 也可以根据应用场景需要来实现`RejectedExecutionHandler`接口自定义策略。如记录日志或持久化存储不能处理的任务。

空闲存活时间配置：
- 任务很多，并且每个任务执行的时间比较短，可以调大时间，提高线程的利用率。

### 监控线程池

通过线程池提供的参数进行监控，在监控线程池的时候可以使用以下属性：

- `taskCount`：线程池需要执行的任务数量。
- `completedTaskCount`：线程池在运行过程中已完成的任务数量，小于或等于`taskCount`。
- `largestPoolSize`：线程池里曾经创建过的最大线程数量。通过这个数据可以知道线程池是否曾经满过。如该数值等于线程池的最大大小，则表示线程池曾经满过。
- `getPoolSize`：线程池的线程数量。
- `getActiveCount`：获取活动的线程数量。

通过继承线程池来自定义线程池，重写线程池的`beforeExecute`、`afterExecute`和`terminated`方法，在任务执行前、执行后和线程池关闭前执行一些代码来进行监控。

## Executor框架

- `FixedThreadPool`：容量为`Integer.MAX_VALUE`的`LinkedBlockingQueue`。由于使用无界队列，因此`maximumPoolSize`和`keepAliveTime`将是无效参数。运行中的FixedThreadPool（未执行方法`shutdown()`或`shutdownNow()`）也不会拒绝任务。这意味着如果主线程提交任务的速度高于池中线程处理任务的速度时，它会不断积压任务。<u>极端情况下，会因为积压过多的任务而耗尽内存资源。</u>
> 适用于为了满足资源管理的需求，而需要限制当前线程数量的应用场景，它适用于负载比较重的服务器。
- `SingleThreadExecutor`：`corePoolSize`和`maximumPoolSize`被设置为`1`，容量为`Integer.MAX_VALUE`的`LinkedBlockingQueue`。使用无界队列带来的影响与上述相同。
> 适用于需要保证顺序地执行各个任务；并且在任意时间点，不会有多个线程是活动的应用场景。
- `CachedThreadPool`：核心线程数为`0`,最大线程数为`Integer.MAX_VALUE`，`keepAliveTime`设置为`60L`，没有容量的`SynchronousQueue`，是大小无界的线程池，这意味着如果主线程提交任务的速度高于池中线程处理任务的速度时，它会不断创建新线程。<u>极端情况下，会因为创建过多线程而耗尽CPU和内存资源。</u>
> 适用于执行很多的短期异步任务的小程序，或者是负载较轻的服务器。
- `ScheduledThreadPoolExecutor`：`DelayedQueue`无界队列，其内保存的`ScheduledFutureTask`任务会先按照任务的执行时间升序排列，其次按照任务提交的序列号升序排列。
> 适用于需要多个后台线程执行周期任务，同时为了满足资源管理的需求而需要限制后台线程的数量的应用场景。
- `SingleThreadScheduledExecutor`：只有一个核心线程的`ScheduledThreadPoolExecutor`。
> 适用于需要单个后台线程执行周期任务，同时需要保证顺序地执行各个任务的应用场景。

----
* *《Java并发编程的艺术》*
* [Synchronization](https://wiki.openjdk.java.net/display/HotSpot/Synchronization)
* [Java Synchronised机制](https://blog.dreamtobe.cn/2015/11/13/java_synchronized/)