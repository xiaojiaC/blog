---
title: Log4j2同步打印日志导致业务线程阻塞
date: 2024-08-24 10:34:23
categories:
  - [JAVA, Log4j2]
tags:
  - log4j2
---

## 背景

日志打印想必对于我们并不陌生，大部分项目我都是配置的同步日志，未发现有性能问题，直到入坑的那天，压测发现权益推荐服务 QPS 才达到 100，TP999 就开始急剧飙升不可逆转。该服务依赖大约 30 多个不同业务的 RPC 权益上游，系统统一对 RPC 调用异常做了捕获处理，理论上不会对服务产生影响，但实际情况却是随着流量上涨，服务 TP999 变长，吞吐量出现急剧下降。

<!-- more -->

当前项目 Log4j2 配置文件如下所示，版本是**2.18.0**：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- 日志级别以及优先级排序: OFF > FATAL > ERROR > WARN > INFO > DEBUG > TRACE > ALL -->
<!-- status="WARN"：用于设置log4j2自身内部日志的信息输出级别，默认是OFF
     monitorInterval="30"：间隔秒数，自动检测配置文件的变更和重置配置
 -->
<Configuration status="WARN">
    <Properties>
        <!-- 模式字符串：
           %d：日期
           %-5level：日志级别从左显示5个字符宽度
           %thread: 输出产生该日志事件的线程名
           %class：是输出的类
           %L: 输出代码中的行号
           %M：方法名
           %msg：日志消息
           %n：换行符
           %c: 输出日志信息所属的类目，通常就是所在类的全名
           %t: 输出产生该日志事件的线程名
           %l: 输出日志事件的发生位置，相当于%C.%M(%F:%L)的组合：包括类目名、发生的线程以及在代码中的行数
           %p: 输出日志信息优先级，即DEBUG，INFO，WARN，ERROR，FATAL
           -->
        <Property name="LOG_EXCEPTION_CONVERSION_WORD">%xwEx</Property>
        <Property name="LOG_LEVEL_PATTERN">%5p</Property>
        <Property name="LOG_DATEFORMAT_PATTERN">yyyy-MM-dd HH:mm:ss.SSS</Property>
        <Property name="CONSOLE_LOG_PATTERN">%clr{%d{${LOG_DATEFORMAT_PATTERN}}}{faint} %clr{${LOG_LEVEL_PATTERN}} %clr{%pid}{magenta} %clr{---}{faint} %clr{[%15.15t]}{faint} %clr{%-40.40c{1.}}{cyan} %clr{:}{faint} %m%n${sys:LOG_EXCEPTION_CONVERSION_WORD}</Property>
        <Property name="FILE_LOG_PATTERN">%d{${LOG_DATEFORMAT_PATTERN}} ${LOG_LEVEL_PATTERN} %X{TRACE_ID} %X{FORCE_BOT} %pid -- [%t] %X{PIN} %c{1} : %m%n${sys:LOG_EXCEPTION_CONVERSION_WORD}</Property>
    </Properties>
    <Appenders>
        <RollingRandomAccessFile name="ALL_FILE" immediateFlush="false"
                                 fileName="/export/logs/server.log"
                                 filePattern="/export/logs/server.log.%d{yyyy-MM-dd}-%i">
            <PatternLayout pattern="${sys:FILE_LOG_PATTERN}">
            </PatternLayout>
            <Policies>
                <TimeBasedTriggeringPolicy />
                <SizeBasedTriggeringPolicy size="1024MB"/>
            </Policies>
            <DefaultRolloverStrategy max="5"/>
        </RollingRandomAccessFile>
        <RollingRandomAccessFile name="ERROR_FILE" immediateFlush="true"
                                 fileName="/export/logs/error.log"
                                 filePattern="/export/logs/error.log.%d{yyyy-MM-dd}-%i">
            <PatternLayout pattern="${sys:FILE_LOG_PATTERN}">
            </PatternLayout>
            <ThresholdFilter level="ERROR" onMatch="ACCEPT" onMismatch="DENY"/>
            <Policies>
                <TimeBasedTriggeringPolicy />
                <SizeBasedTriggeringPolicy size="1024MB"/>
            </Policies>
            <DefaultRolloverStrategy max="3"/>
        </RollingRandomAccessFile>
        <Console name="STDOUT" target="SYSTEM_OUT">
            <PatternLayout pattern="${sys:FILE_LOG_PATTERN}"/>
        </Console>
    </Appenders>
    <Loggers>
        <!-- additivity="false": additivity设置事件是否在root logger输出，为了避免重复输出，
        可以在Logger标签下设置additivity为false只在自定义的Appender中进行输出 -->
        <Logger name="com.xxx" level="INFO" />

        <Root level="ERROR">
            <AppenderRef ref="ALL_FILE"/>
            <AppenderRef ref="ERROR_FILE"/>
        </Root>
    </Loggers>
</Configuration>
```

### 问题分析

到底是什么导致性能急剧下降？先到压测机上保存下线程现场，打开 jstack 文件就被眼前的景象呆住了：

{% asset_img jstack-info.png java堆栈 %}

1200+业务线程均被阻塞在`org.apache.catalina.loader.WebappClassLoaderBase.loadClass`，为什么会导致阻塞呢？定位到该代码点：

```java
@Override
public Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
    synchronized (JreCompat.isGraalAvailable() ? this : getClassLoadingLock(name)) { // 这里有并行类加载同步锁
        if (log.isDebugEnabled()) {
            log.debug("loadClass(" + name + ", " + resolve + ")");
        }
        Class<?> clazz = null;

        // 检查应用程序是否已停止，停止则抛异常拒绝加载
        checkStateForClassLoading(name);

        // (0) 检查我们之前加载的本地类缓存（该类的resourceEntries缓存Map）
        clazz = findLoadedClass0(name);
        if (clazz != null) {
            if (log.isDebugEnabled()) {
                log.debug("  Returning class from cache");
            }
            if (resolve) {
                resolveClass(clazz);
            }
            return clazz;
        }

        // (0.1) 检查我们之前加载的类缓存
        clazz = JreCompat.isGraalAvailable() ? null : findLoadedClass(name);
        if (clazz != null) {
            if (log.isDebugEnabled()) {
                log.debug("  Returning class from cache");
            }
            if (resolve) {
                resolveClass(clazz);
            }
            return clazz;
        }

        // (0.2) 尝试使用引导类加载器加载类，以防止Web应用程序覆盖JavaSE类
        String resourceName = binaryNameToPath(name, false);

        ClassLoader javaseLoader = getJavaseClassLoader(); // 这里debug是ExtClassLoader
        boolean tryLoadingFromJavaseLoader;
        try {
            // Use getResource as it won't trigger an expensive
            // ClassNotFoundException if the resource is not available from
            // the Java SE class loader. However (see
            // https://bz.apache.org/bugzilla/show_bug.cgi?id=58125 for
            // details) when running under a security manager in rare cases
            // this call may trigger a ClassCircularityError.
            // See https://bz.apache.org/bugzilla/show_bug.cgi?id=61424 for
            // details of how this may trigger a StackOverflowError
            // Given these reported errors, catch Throwable to ensure any
            // other edge cases are also caught
            URL url;
            if (securityManager != null) {
                PrivilegedAction<URL> dp = new PrivilegedJavaseGetResource(resourceName);
                url = AccessController.doPrivileged(dp);
            } else {
                url = javaseLoader.getResource(resourceName);
            }
            tryLoadingFromJavaseLoader = (url != null);
        } catch (Throwable t) {
            // Swallow all exceptions apart from those that must be re-thrown
            ExceptionUtils.handleThrowable(t);
            // The getResource() trick won't work for this class. We have to
            // try loading it directly and accept that we might get a
            // ClassNotFoundException.
            tryLoadingFromJavaseLoader = true;
        }

        if (tryLoadingFromJavaseLoader) {
            try {
                clazz = javaseLoader.loadClass(name);
                if (clazz != null) {
                    if (resolve) {
                        resolveClass(clazz);
                    }
                    return clazz;
                }
            } catch (ClassNotFoundException e) {
                // Ignore
            }
        }

        // (0.5) Permission to access this class when using a SecurityManager
        if (securityManager != null) {
            int i = name.lastIndexOf('.');
            if (i >= 0) {
                try {
                    securityManager.checkPackageAccess(name.substring(0,i));
                } catch (SecurityException se) {
                    String error = sm.getString("webappClassLoader.restrictedPackage", name);
                    log.info(error, se);
                    throw new ClassNotFoundException(error, se);
                }
            }
        }

        // (1) 如果被要求或者是内部的一些类，委托给父加载器加载（这里我们显然都不符合）
        boolean delegateLoad = delegate || filter(name, true); // eg. 名字以javax、org.apache.catalina开头的类等
        if (delegateLoad) {
            if (log.isDebugEnabled()) {
                log.debug("  Delegating to parent classloader1 " + parent);
            }
            try {
                clazz = Class.forName(name, false, parent);
                if (clazz != null) {
                    if (log.isDebugEnabled()) {
                        log.debug("  Loading class from parent");
                    }
                    if (resolve) {
                        resolveClass(clazz);
                    }
                    return clazz;
                }
            } catch (ClassNotFoundException e) {
                // Ignore
            }
        }

        // (2) 在我们的本地存储库中尝试找指定的类
        if (log.isDebugEnabled()) {
            log.debug("  Searching local repositories");
        }
        try {
            clazz = findClass(name);
            if (clazz != null) {
                if (log.isDebugEnabled()) {
                    log.debug("  Loading class from local repository");
                }
                if (resolve) {
                    resolveClass(clazz);
                }
                return clazz;
            }
        } catch (ClassNotFoundException e) {
            // Ignore
        }

        // (3) 还无法加载，最后再无条件委托给父加载器尝试一下（父类加载器是URLClassLoader，也是加载不到的）
        if (!delegateLoad) {
            if (log.isDebugEnabled()) {
                log.debug("  Delegating to parent classloader at end: " + parent);
            }
            try {
                clazz = Class.forName(name, false, parent);
                if (clazz != null) {
                    if (log.isDebugEnabled()) {
                        log.debug("  Loading class from parent");
                    }
                    if (resolve) {
                        resolveClass(clazz);
                    }
                    return clazz;
                }
            } catch (ClassNotFoundException e) {
                // Ignore
            }
        }
    }

    throw new ClassNotFoundException(name);
}
```

从上面代码可以看到，压测中线程阻塞在`org.apache.catalina.loader.WebappClassLoaderBase#loadClass(java.lang.String, boolean)`，这个方法的代码中包含`synchronized`同步代码块。其内会调用`java.lang.ClassLoader#getClassLoadingLock`获取 JDK 并行类加载锁。`org.apache.catalina.loader.WebappClassLoader`究竟在加载什么类呢？又为什么需要这么长的时间呢？本地通过 JDWP 连远程机器 DEBUG 看下：

{% asset_img loadClass.jpg %}

结合上述 Log4j2 日志配置和蓝框中调用栈，得知我们打印日志使用的是`PatternLayout`，其内配置了`%xwEx`模式字符串，触发了`ExtendedThrowablePatternConverter`转换器解析异常栈信息，在转换中会获取每个调用栈的`Class`信息，从而诱发相关类的加载。

> 注意：如果模式串不包含处理 Throwable 的标识符，那么会将`%xEx`添加到模式串的末尾进行解析。`%xEx`与`%throwable`相同，但还包括类的包信息。throwable 转换字后面可以跟一个`%xEx{short}`形式的选项，该选项将仅输出 Throwable 的第一行或`%xEx{n}`将打印堆栈跟踪的前 n 行。指定`%xEx{none}`或`%xEx{0}`将禁止打印异常。具体可以看[Log4j2 PatternLayout](https://logging.apache.org/log4j/2.x/manual/layouts.html#pattern-layout)查阅。

调用栈的大部分的`Class`信息可以从`StackLocatorUtil.getCurrentStackTrace()`中直接获取，不需要类加载。但`GeneratedMethodAccessorXxx`无法直接获取，经过一个复杂的类加载后仍然没有加载到。

#### JVM 类加载机制

在分析类加载的过程前，我们先回顾下 JVM 类加载机制：

- JVM 类加载机制

JVM 把描述类的数据从`.class`文件加载到内存，并对数据进行校验、链接和初始化后，最终形成可以被 JVM 直接使用的 Java 类型（`Java.lang.Class`对象），这就是 JVM 的类加载机制。JVM 的类加载是通过`ClassLoader`及其子类来完成的，类的层次关系和加载顺序可以由下图来描述：

{% asset_img JVM类加载机制.png %}

JVM 在加载类时默认采用的是双亲委派机制，即一个类收到加载类的请求时，它并不会自己先去加载，而是把加载任务委托给父类加载器依次递归，所有的加载请求最终都应该传送到顶层的引导类加载器中。如果父类加载器可以完成这个类加载请求，就成功返回；当父类加载器无法完成此加载请求时，子加载器才会尝试自己去加载。通过这种层级关系可以避免类的重复加载，同时保障核心类不被篡改。

- 线程上下文类加载器

Java 1.2 引入`ThreadContextClassLoader`即 TCCL，作为一个线程本地变量的和某个线程关联在一起的一个类加载器。这能够让任何包都可以在任意时候通过当前调用线程访问当前上下文加载器。这一上下文加载器能够访问负责本次调用的特定应用类加载器，然后能够对应用的类进行访问。

#### `GeneratedMethodAccessorXxx`类加载过程

`GeneratedMethodAccessorXxx`类的加载过程，整体分为 3 次：

1. 第一次类加载，`lastLoader == WebappClassLoader`，使用自己加载，无法加载到类信息。

{% asset_img loadClass_1.png %}

2. 第二次类加载，`tccl == WebappClassLoader`，类同步骤 1 自然也是无法加载到了。

{% asset_img loadClass_2.jpg %}

3. 第三次类加载，`ThrowableProxyHelper.class.getClassLoader()`类的加载器也是`WebappClassLoader`，同理无法加载。

{% asset_img loadClass_3.jpg %}

那`WebappClassLoader`中到底是如何加载的呢？整体又分为 6 步：

1. 检查我们之前加载的本地类缓存（该类已加载过的类缓存在`resourceEntries` Map，此时还未加载过因此没有）；
2. 检查我们之前加载的类缓存（jvm 内已加载过的类缓存，也没有）；

{% asset_img loadClass_1_2.jpg %}

3. 尝试使用`javaseLoader == Launcher$ExtClassLoader`类加载器加载类，以防止 Web 应用程序覆盖 JavaSE 类；

{% asset_img loadClass_1_3.jpg %}

4. 如果被要求委托或者是内部的一些类，委托给父类加载器加载（这里我们显然都不符合）；
5. 在我们的本地存储库中尝试找指定的类；
6. 还无法加载，最后再无条件委托给父类加载器尝试一下（父类加载器是`URLClassLoader`，也没加载到）。

`org.apache.catalina.loader.WebappClassLoader`类的加载器层级如下图所示：

{% asset_img classLoader.jpg %}

那为什么`GeneratedMethodAccessorXxx`类无法加载到呢？

由于应用依赖大量上游 RPC 调用，我们知道像[DUBBO](https://cn.dubbo.apache.org/zh-cn/#/docs/user/quick-start.md?lang=zh-cn)类似的微服务框架，内部其实是组装好消息对象（包含接口、方法名、别名、参数类型、参数值等）调用目标机，反射执行远程方法调用。我们的服务 Provider 接收到消息后，并行请求 30 多个上游获取权益，其中任何一个调用异常就会打印异常栈，继而诱发`GeneratedMethodAccessorXxx`类加载。

这个过程使用`Method.invoke`反射。在`sun.reflect`包中`Method.invoke`使用代理类，代理类有如下 2 种方式实现：

- `NativeMethodAccessorImpl`
- `GeneratedMethodAccessorXxx`

这 2 个代理类都包含`invoke`方法，都能完成对反射类方法的调用。不同点是：

1. `NativeMethodAccessorImpl`通过 new 方法生成，`invoke`方法底层调用 native 方法；
2. `GeneratedMethodAccessorXxx`通过 bytecode 动态生成。前 16 次调用使用`NativeMethodAccessorImpl`，从 17 次调用开始使用`GeneratedMethodAccessorXxx`，这种方式称为 Inflation 机制。

为什么这设计呢？源码注释如下：

> "Inflation" mechanism. Loading bytecodes to implement Method.invoke() and Constructor.newInstance() currently costs 3-4x more than an invocation via native code for the first invocation (though subsequent invocations have been benchmarked to be over 20x faster). Unfortunately this cost increases startup time for certain applications that use reflection intensively (but only once per class) to bootstrap themselves. To avoid this penalty we reuse the existing JVM entry points for the first few invocations of Methods and Constructors and then switch to the bytecode-based implementations.

含义大概是对于第一次`Method.invoke`调用，使用`GeneratedMethodAccessorXxx`会比`NativeMethodAccessorImpl`时间多 3-4 倍，这对于密集使用反射（每个类只有一次）作为引导启动的应用来说，增加了应用的启动时间。因此前几次会使用`NativeMethodAccessorImpl`，之后会切换到`GeneratedMethodAccessorXxx`。这个次数可以通过 JVM 参数`-Dsun.reflect.inflationThreshold`进行配置，默认是 15，设置为 0 即为直接绕过`NativeMethodAccessorImpl`调用，和设置`-Dsun.reflect.noInflation=true`参数的效果一样。

`GeneratedMethodAccessorXxx`动态生成的类具体是什么呢？大概长这样：

```java
/**
 * ClassLoader:
 * +-sun.reflect.DelegatingClassLoader
 *   +-sun.misc.Launcher$AppClassLoader
 *     +-sun.misc.Launcher$ExtClassLoader
 */
package sun.reflect;

import java.lang.reflect.InvocationTargetException;
import sun.reflect.MethodAccessorImpl;
import com.xxx.TargetClass;

public class GeneratedMethodAccessorXxx extends MethodAccessorImpl {

    public GeneratedMethodAccessorXxx() { super(); }

    public Object invoke(Object object, Object[] args)
            throws IllegalArgumentException, InvocationTargetException {
        if (object == null) {
            throw new NullPointerException();
        }
        try {
            TargetClass target = (TargetClass) object;
            if (args != null && args.length > 0) {
                throw new IllegalArgumentException();
            }
            // 这里假设我们是对 TargetClass.targetMethod() 空参方法的访问
            return target.targetMethod();
        } catch (Throwable throwable) {
            throw new InvocationTargetException(throwable);
        } catch (ClassCastException | NullPointerException e) {
            throw new IllegalArgumentException(e.toString());
        }
    }
}
```

其实内部就是直接调用目标对象的目标方法，和正常的方法调用没什么区别。

#### `GeneratedMethodAccessorXxx`的类加载器

那加载`GeneratedMethodAccessorXxx`的类加载器是什么呢，在生成好了字节码之后会调用下面的方法做类定义：

```java
package sun.reflect;

import java.security.AccessController;
import java.security.PrivilegedAction;
import java.security.ProtectionDomain;
import sun.misc.Unsafe;

class ClassDefiner {
    static final Unsafe unsafe = Unsafe.getUnsafe();

    ClassDefiner() {
    }

    static Class<?> defineClass(String var0, byte[] var1, int var2, int var3, final ClassLoader var4) {
        ClassLoader var5 = (ClassLoader)AccessController.doPrivileged(new PrivilegedAction<ClassLoader>() {
            public ClassLoader run() {
                return new DelegatingClassLoader(var4);
            }
        });
        return unsafe.defineClass(var0, var1, var2, var3, var5, (ProtectionDomain)null);
    }
}
```

所以`GeneratedMethodAccessorXxx`的类加载器其实是一个`DelegatingClassLoader`类加载器。

在 Java 中，类的加载是由类加载器负责的。当需要动态生成类时，为了性能考虑，会创建一个新的类加载器，即`DelegatingClassLoader`，来加载这些动态生成的类。这样做的原因是为了能够在需要时创建这些类，而在内存紧张时能够释放这些类的内存。如果使用原有的类加载器，可能会导致新创建的类无法被卸载，因为类的卸载只有在类加载器可以被回收的情况下才会发生。因此通过使用`DelegatingClassLoader`，可以更好地管理内存，避免内存泄漏。

结合以上类加载过程以及`GeneratedMethodAccessorXxx`类的生成方式，可知无法加载到的原因如下：

1. `GeneratedMethodAccessorXxx`是动态生成的类，`.class`文件无法在磁盘中查找到，所以通过其他的类加载器无法进行类加载。
2. `GeneratedMethodAccessorXxx`的类加载器是`DelegatingClassLoader`，而 Log4j2 并没有使用此加载器来获取，所以也不会加载到。

### 小结

通过以上分析，总结如下：

1. 日志 Layout 默认使用`%xEx`打印异常栈的类信息，而异常栈中包含动态类`GeneratedMethodAccessorXxx`的加载，需要进行类加载；
2. Log4j2 最终调用`WebappClassLoader.loadclass`进行类加载，由于是动态类和类加载器使用的原因，导致无法加载。每次日志打印都会进行类加载过程，而在`loadClass`的方法中有`synchronized`发生同步等待，线程阻塞后，并发能力下降。

### 优化

问题原因比较清楚了，那么我们怎么来优化呢？

1. 在`Layout`中增加标识符`%xEx{n}`，**n**表示打印多少行栈信息，一般只需要把业务调用栈信息打印出来即可，框架栈信息不需要。或者使用`%xEx{0}`来禁用打印异常栈，但显然生产环境不适用。
2. 改用异步日志打印。因为日志打印发生在异步线程中，业务线程无感知，因此能够比较好的解决这个问题。

#### Log4J2 日志分类

先来回顾下 Log4j2 中的主要组件：

{% asset_img Log4jClasses.jpg %}

Log4j2 中记录日志的方式有同步日志和异步日志两种方式，其中异步日志又可分为使用`AsyncAppender`和使用`AsyncLogger`两种方式。使用 Log4j2 有三种日志模式：全局异步日志、混合异步日志、同步日志，[性能](https://logging.apache.org/log4j/2.x/performance.html)从高到底，线程越多效率越高，也可以避免日志卡死线程情况发生。

- 同步日志：同步打印日志，日志输出与业务逻辑在同一线程，当日志输出完毕，才能继续后续业务逻辑处理。
- `AsyncAppender`：异步打印日志，内部采用`ArrayBlockingQueue`，对每个`AsyncAppender`创建一个线程用于处理日志输出。
- `AsyncLogger`：异步打印日志，内部采用高性能并发框架`Disruptor`，创建一个线程用于处理日志输出。

##### `Disruptor`vs`ArrayBlockingQueue`

- 多线程访问队列时，`ArrayBlockingQueue`采用的`ReentrantLock`重量级锁，而`Disruptor`采用`CAS`的方式。
- `Disruptor`队列中的关键属性之间会被填充冗余字段，比如队列头和队列尾，从而使得不同的属性位于不同的 cpu 缓存行上，当生产者和消费者分别并发的对其进行修改时，可以避免缓存失效。
- `Disruptor`使用环形队列`RingBuffer`，和`ArrayBlockingQueue`不同，`RingBuffer`不需要频繁地分配和释放，可以避免分配带来的消耗，避免垃圾回收，同时可以更好地利用 CPU 的缓存机制更加友好。

> [Disruptor 详解](https://www.jianshu.com/p/bad7b4b44e48)

#### `AsyncAppender`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="warn">
    <Appenders>
        <RollingRandomAccessFile name="ALL_FILE" immediateFlush="false"
                                 fileName="/export/logs/server.log"
                                 filePattern="/export/logs/server.log.%d{yyyy-MM-dd}-%i">
            <PatternLayout pattern="${sys:FILE_LOG_PATTERN}">
            </PatternLayout>
            <Policies>
                <TimeBasedTriggeringPolicy />
                <SizeBasedTriggeringPolicy size="1024MB"/>
            </Policies>
            <DefaultRolloverStrategy max="5"/>
        </RollingRandomAccessFile>
        <!-- 异步AsyncAppender进行配置直接引用上面的RollingRandomAccessFile的name -->
        <Async name="Async">
              <AppenderRef ref="ALL_FILE"/>
        </Async>
        <!-- 异步AsyncAppender配置完毕，需要几个配置几个 -->
    </Appenders>

    <Loggers>
        <Root level="error">
            <!-- 此处如果引用异步AsyncAppender的name就是异步输出日志 -->
            <!-- 此处如果引用Appenders标签中RollingRandomAccessFile的name就是同步输出日志 -->
            <AppenderRef ref="Async"/>
        </Root>
    </Loggers>
</Configuration>
```

#### `AsyncLogger`

`AsyncLogger`才是 log4j2 的重头戏，也是官方推荐的异步方式。Log4j2 中的`AsyncLogger`的内部使用了[Disruptor](https://lmax-exchange.github.io/disruptor/)框架。

异步日志可以有两种选择：全局异步和混合异步。开启异步首先需要引入`Disruptor`依赖：

```xml
<dependency>
  <groupId>com.lmax</groupId>
  <artifactId>disruptor</artifactId>
  <version>3.4.2</version>
</dependency>
```

- 全局异步

全局异步就是：所有的日志都异步的记录，在原 Log4j2 配置文件上不用做任何改动，只需要在 JVM 启动的时候增加一个参数，这是最简单的配置，并提供最佳性能。

也可以在`src/java/resources`目录添加`log4j2.system.properties`配置文件（其他支持的配置源，请参阅[Log4j2 System Properties](https://logging.apache.org/log4j/2.x/manual/configuration.html#system-properties)），内容如下：

```
log4j2.contextSelector=org.apache.logging.log4j.core.async.AsyncLoggerContextSelector
log4j2.asyncQueueFullPolicy=Discard
log4j2.discardThreshold=ERROR
```

{% asset_img 全局异步日志.png 全局异步日志运行原理图 %}

- 混合异步

混合异步就是：可以在应用中同时使用同步日志和异步日志，这使得日志的配置方式更加灵活。虽然 Log4j2 提供以一套异常处理机制，可以覆盖大部分的状态，但是还是会有一小部分的特殊情况是无法完全处理的，比如我们如果是记录审计日志，那么官方就推荐使用同步日志的方式，而对于记录业务日志的地方，使用异步日志将大幅提升性能，减少对应用本身的影响。混合异步的方式需要通过修改 Log4j2 配置文件来实现，通过将`<Root>`或`<Logger>`元素替换为`<AsyncRoot>`或`<AsyncLogger>`。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Configuration status="WARN">
    <Properties>
        <Property name="LOG_EXCEPTION_CONVERSION_WORD">%xwEx</Property>
        <Property name="LOG_LEVEL_PATTERN">%5p</Property>
        <Property name="LOG_DATEFORMAT_PATTERN">yyyy-MM-dd HH:mm:ss.SSS</Property>
        <Property name="CONSOLE_LOG_PATTERN">%clr{%d{${LOG_DATEFORMAT_PATTERN}}}{faint} %clr{${LOG_LEVEL_PATTERN}} %clr{%pid}{magenta} %clr{---}{faint} %clr{[%15.15t]}{faint} %clr{%-40.40c{1.}}{cyan} %clr{:}{faint} %m%n${sys:LOG_EXCEPTION_CONVERSION_WORD}</Property>
        <Property name="FILE_LOG_PATTERN">%d{${LOG_DATEFORMAT_PATTERN}} ${LOG_LEVEL_PATTERN} %X{TRACE_ID} %X{FORCE_BOT} %pid -- [%t] %X{PIN} %c{1} : %m%n${sys:LOG_EXCEPTION_CONVERSION_WORD}</Property>
    </Properties>
    <Appenders>
        <RollingRandomAccessFile name="ALL_FILE" immediateFlush="false"
                                 fileName="/export/logs/server.log"
                                 filePattern="/export/logs/server.log.%d{yyyy-MM-dd}-%i">
            <PatternLayout pattern="${sys:FILE_LOG_PATTERN}">
            </PatternLayout>
            <Policies>
                <TimeBasedTriggeringPolicy />
                <SizeBasedTriggeringPolicy size="1024MB"/>
            </Policies>
            <DefaultRolloverStrategy max="5"/>
        </RollingRandomAccessFile>
        <RollingRandomAccessFile name="ERROR_FILE" immediateFlush="true"
                                 fileName="/export/logs/error.log"
                                 filePattern="/export/logs/error.log.%d{yyyy-MM-dd}-%i">
            <PatternLayout pattern="${sys:FILE_LOG_PATTERN}">
            </PatternLayout>
            <ThresholdFilter level="ERROR" onMatch="ACCEPT" onMismatch="DENY"/>
            <Policies>
                <TimeBasedTriggeringPolicy />
                <SizeBasedTriggeringPolicy size="1024MB"/>
            </Policies>
            <DefaultRolloverStrategy max="3"/>
        </RollingRandomAccessFile>
        <Console name="STDOUT" target="SYSTEM_OUT">
            <PatternLayout pattern="${sys:FILE_LOG_PATTERN}"/>
        </Console>
    </Appenders>
    <Loggers>
        <!-- 定义一个同步Logger并使用Root下Appender引用 -->
        <Logger name="com.xxx" level="INFO" />
        <Root level="ERROR">
            <AppenderRef ref="ALL_FILE"/>
            <AppenderRef ref="ERROR_FILE"/>
        </Root>
        <!-- 定义一个异步Logger并为其配置普通Appender引用 -->
        <AsyncLogger name="AsyncLogger" level="INFO" includeLocation="false" additivity="false">
           <appender-ref ref="ALL_FILE"/>
        </AsyncLogger>
    </Loggers>
</Configuration>
```

#### location 信息对性能的影响

在`LayoutPattern`中，`%C`或`%class`, `%F`或`%file`，`%l`或`%location`，`%L`或`%line`，`%M`或`%method`都会采用`new Throwable().getStackTrace()`的方式获取了当前日志操作所在的堆栈快照，日志操作方法（比如`log.info()`）的下一个栈帧就是当前 log 所处的方法，这是一种非常耗时的操作。

替换方法：

在`LayoutPattern`中使用`%c`或`%logger`，这种方式可以记录**logger**的 name，在日常开发中，**logger**的 name 一般都是当前 logger 所在类的 class 全限定名。比如`Logger log = LoggerFactory.getLogger(Demo.class);`，lombok 的`@Slf4j`, `@Log4j`, `@Log4j2`注解也同样遵循这种方式。

#### 配置信息

| 名称                                                                                      | 默认值                                         | 描述                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ----------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `RingBuffer`槽位数量：`log4j2.asyncLoggerConfigRingBufferSize`（同步&异步混合使用）       | 256 * 1024（garbage-free 模式下默认为 4*1024） | 最小值为 128（2 的幂次），在首次使用的时候进行分配，并固定大小                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| 异步日志等待策略：`log4j2.asyncLoggerConfigWaitStrategy`（同步&异步混合使用）             | `Timeout`                                      | `Block`：I/O 线程使用锁和条件变量等待可用的日志事件，建议在 CPU 资源重要程度大于系统吞吐和延迟的情况下使用该种策略； `Timeout`：是 Block 策略的一个变体，可以确保如果线程没有被及时唤醒（`awit()`）的话，线程也不会卡在那里，可以以一个较小的延迟（默认 10ms）恢复； `Sleep`：是一种自旋策略，使用纳秒级别的自旋交叉执行`Thread.yield()`和`LockSupport.parkNanos()`，该种策略可以较好的平衡系统性能和 CPU 资源的使用率，并且对程序线程影响较小； `Yield`：相较于`Sleep`省去了`LockSupport.parkNanos()`，而是不断执行`Thread.yield()`来让渡 CPU 使用权，但是会造成 CPU 一直处于较高负载，**不建议**在生产环境使用该种策略 |
| `RingBuffer`槽位数量：`log4j2.asyncLoggerRingBufferSize`（纯异步）                        | 256 * 1024（garbage-free 模式下默认为 4*1024） | 同上                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 异步日志等待策略：`log4j2.asyncLoggerWaitStrategy`（纯异步）                              | `Timeout`                                      | 同上                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 异步队列满后执行策略：`log4j2.asyncQueueFullPolicy`                                       | `Default`                                      | 当 Appender 的日志消费速度跟不上日志的生产速度，且队列已满时，指定如何处理尚未正常打印的日志事件，默认为阻塞（Default），**建议**配置为丢弃（`Discard`）                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| 日志丢弃阈值：`log4j2.discardThreshold`                                                   | `INFO`                                         | 当`Appender`的消费速度跟不上日志记录的速度，且队列已满时，若`log4j2.asyncQueueFullPolicy`为`Discard`，该配置用于指定丢弃的日志事件级别（小于等于），默认为`INFO`级别（即将`INFO`、`DEBUG`、`TRACE`日志事件丢弃掉）， **建议**设置为`ERROR`（`FATAL`虽然有些极端，但是也可以）                                                                                                                                                                                                                                                                                                                                            |
| 异步日志超时时间：`log4j2.asyncLoggerTimeout`                                             | 10                                             | 异步日志等待策略为`Timeout`时，指定超时时间（单位：ms）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| 异步日志睡眠时间：`log4j2.asyncLoggerSleepTimeNs`                                         | 100                                            | 异步日志等待策略为`Sleep`时，线程睡眠时间（单位：ns）                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 异步日志重试次数：`log4j2.asyncLoggerRetries`                                             | 200                                            | 异步日志等待策略为`Sleep`时，自旋重试次数                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| 队列满时是否将对`RingBuffer`的访问转为同步：`AsyncLogger.SynchronizeEnqueueWhenQueueFull` | true                                           | 当队列满时是否将对`RingBuffer`的访问转为同步，当`Appender`日志消费速度跟不上日志的生产速度，且队列已满时，通过限制对队列的访问，可以显著降低 CPU 资源的使用率，**建议**使用该默认配置                                                                                                                                                                                                                                                                                                                                                                                                                                    |

#### 配置建议

- 建议在`Configuration`标签中添加`monitorInterval`属性，以支持配置动态刷新。
- 建议使用`RollingRandomAccessFile`做为 Appender。
- 对于日志输出频繁且大量的应用，应配置基于大小和时间的双重文件滚动策略。
- `ERROR`等报错日志额外记录一份日志文件, 同时允许`INFO`日志文件中存在`ERROR`日志或植入链路追踪 ID，以便于排查问题。
- 建议日志滚动、压缩等耗费性能的操作，配置在非整点进行，避开可能即将开始的业务活动。
- 建议使用异步模式。但不要同时使用`AsyncAppender`和`AsyncLogger`，这做不会报错，但是对于性能提升没有任何好处。
- 建议在子`Logger`或子`AsyncLogger`中设置`additivity="false"`，避免日志重复打印。
- 建议设置`includeLocation="false"`，同时`PatternLayout`不要使用`%L`、`%C`、`%M`等含有位置信息的模式串，可以使用`%c`或`%logger`代替。
- 当日志产生速度大于 Appender 记录速度时，队列会被填满，应用线程将会阻塞。可以设置`log4j2.AsyncQueueFullPolicy=Discard`配合`log4j2.discardThreshold=ERROR`，在队列满时丢弃小于等于指定阈值日志（默认为`INFO`级别，即将`INFO`，`DEBUG`，`TRACE`日志事件丢弃掉）。
- 建议使用`RandomAccessFileAppender`, 并且设置`immediateFlush="false"`避免频繁刷盘，但注意设置后`tail -f`将不能实时观察最新日志。

> [Log4j2 Async](https://logging.apache.org/log4j/2.x/manual/async.html)
