---
title: Spring如何解决循环依赖？
date: 2023-11-01 23:31:11
categories:
  - [JAVA, Spring]
tags:
  - java
  - spring
  - spring core
---

## Spring 如何解决循环依赖？

所谓循环依赖是指：`BeanA`对象的创建依赖于`BeanB`，`BeanB`对象的创建也依赖于`BeanA`，这就造成了死循环，如果不做处理的话势必会造成栈溢出。Spring 通过**提前曝光机制，利用三级缓存**解决循环依赖问题。本文从 Spring 源码入手，剖析最常见的普通 Bean 与普通 Bean 之间循环依赖的解决之道。

### `getBean`

我们先从`getBean`源码入手，熟悉下 Bean 创建过程（源码仅贴相关部分）。

```java org.springframework.beans.factory.support.AbstractBeanFactory.java
public abstract class AbstractBeanFactory extends FactoryBeanRegistrySupport implements ConfigurableBeanFactory {

    ......

    @Override
    public Object getBean(String name) throws BeansException {
        return doGetBean(name, null, null, false);
    }

    protected <T> T doGetBean(String name, @Nullable Class<T> requiredType,
            @Nullable Object[] args, boolean typeCheckOnly) throws BeansException {

        // 获取Bean名称
        String beanName = transformedBeanName(name);
        Object bean;

        // 从一二三级缓存中依次获取目标Bean实例
        Object sharedInstance = getSingleton(beanName);
        if (sharedInstance != null && args == null) {
            ......

            // 不为空，则进行后续处理并返回
            bean = getObjectForBeanInstance(sharedInstance, name, beanName, null);
        } else { // 从缓存中没有获取到Bean实例
            ......
            try {
                ......
                RootBeanDefinition mbd = getMergedLocalBeanDefinition(beanName);
                ......

                // 目标Bean是单实例Bean
                if (mbd.isSingleton()) {
                    sharedInstance = getSingleton(beanName, () -> {
                        try {
                            return createBean(beanName, mbd, args); // 创建Bean实例
                        }
                        catch (BeansException ex) {
                            ......
                        }
                    });
                    // 后续处理并返回
                    bean = getObjectForBeanInstance(sharedInstance, name, beanName, mbd);
                }
                ......
            }
            catch (BeansException ex) {
                ......
                throw ex;
            }
        }
        ......
        return (T) bean;
    }

    ......
}
```

`doGetBean`方法中先通过`getSingleton(String beanName)`方法依次从一二三级缓存中获取 Bean 实例，如果不为空则进行后续处理后返回；如果为空，则通过 `getSingleton(String beanName, ObjectFactory<?> singletonFactory)`方法创建 Bean 实例并进行后续处理后返回。

这两个方法都是`AbstractBeanFactory`父类`DefaultSingletonBeanRegistry`中的方法：

{% asset_img AbstractBeanFactory.png AbstractBeanFactory类层级关系图%}

#### `getSingleton(String beanName)`

```java org.springframework.beans.factory.support.DefaultSingletonBeanRegistry.java
public class DefaultSingletonBeanRegistry extends SimpleAliasRegistry implements SingletonBeanRegistry {

    /** Cache of singleton objects: bean name to bean instance. */
    private final Map<String, Object> singletonObjects = new ConcurrentHashMap<>(256); // 一级缓存

    /** Cache of singleton factories: bean name to ObjectFactory. */
    private final Map<String, ObjectFactory<?>> singletonFactories = new HashMap<>(16); // 三级缓存

    /** Cache of early singleton objects: bean name to bean instance. */
    private final Map<String, Object> earlySingletonObjects = new ConcurrentHashMap<>(16); // 二级缓存

    ......

    @Override
    @Nullable
    public Object getSingleton(String beanName) {
        return getSingleton(beanName, true);
    }

    @Nullable
    protected Object getSingleton(String beanName, boolean allowEarlyReference) {
        // 从一级缓存中获取目标Bean实例
        Object singletonObject = this.singletonObjects.get(beanName);
        // 如果没有获取到，并且该Bean处于正在创建中的状态时
        if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
            // 从二级缓存获取目标Bean实例
            singletonObject = this.earlySingletonObjects.get(beanName);
            // 如果没有获取到，并且允许提前曝光的话
            if (singletonObject == null && allowEarlyReference) {
                synchronized (this.singletonObjects) {
                    // 在锁内重新从一级缓存中查找
                    singletonObject = this.singletonObjects.get(beanName);
                    if (singletonObject == null) {
                        // 重新从二级缓存中查找
                        singletonObject = this.earlySingletonObjects.get(beanName);
                        if (singletonObject == null) {
                            // 从三级缓存中取出目标Bean工厂对象
                            ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
                            if (singletonFactory != null) {
                                // 工厂对象不为空，则通过调用getObject方法创建Bean实例
                                singletonObject = singletonFactory.getObject();
                                // 放到二级缓存中
                                this.earlySingletonObjects.put(beanName, singletonObject);
                                // 删除对应的三级缓存
                                this.singletonFactories.remove(beanName);
                            }
                        }
                    }
                }
            }
        }
        return singletonObject;
    }

    ......
}
```

三级缓存指的是`DefaultSingletonBeanRegistry`类的三个成员变量：

| 变量                    | 描述                                                                                                                                                                                                                   |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `singletonObjects`      | 一级缓存，key 为 Bean 名称，value 为 Bean 实例。这里的 Bean 实例指的是已经完全创建好的，即已经经历实例化->属性填充->初始化以及各种后置处理过程的 Bean，可直接使用。                                                    |
| `earlySingletonObjects` | 二级缓存，key 为 Bean 名称，value 为 Bean 实例。这里的 Bean 实例指的是仅完成实例化的 Bean，还未进行属性填充等后续操作。用于提前曝光，供别的 Bean 引用，解决循环依赖。                                                  |
| `singletonFactories`    | 三级缓存，key 为 Bean 名称，value 为 Bean 工厂。在 Bean 实例化后，属性填充之前，如果允许提前曝光，Spring 会把该 Bean 转换成 Bean 工厂并加入到三级缓存。在需要引用提前曝光对象时再通过工厂对象的`getObject()`方法获取。 |

如果通过一二三级缓存的查找都没有找到目标 Bean 实例，则开始执行创建。

#### `getSingleton(String beanName, ObjectFactory<?> singletonFactory)`

```java org.springframework.beans.factory.support.DefaultSingletonBeanRegistry.java
public class DefaultSingletonBeanRegistry extends SimpleAliasRegistry implements SingletonBeanRegistry {

    ......

    public Object getSingleton(String beanName, ObjectFactory<?> singletonFactory) {
        synchronized (this.singletonObjects) {
            // 从一级缓存获取
            Object singletonObject = this.singletonObjects.get(beanName);
            if (singletonObject == null) { // 为空则继续
                ......
                // 将当前Bean名称添加到正在创建Bean的集合（singletonsCurrentlyInCreation）中
                beforeSingletonCreation(beanName);
                boolean newSingleton = false;
                ......
                try {
                    // 通过函数式接口创建Bean实例
                    singletonObject = singletonFactory.getObject();
                    // 创建后该实例已经经历实例化->属性填充->初始化以及各种后置处理过程，可直接使用
                    newSingleton = true;
                }
                catch (IllegalStateException ex) {
                   ......
                }
                finally {
                    ......
                }
                if (newSingleton) {
                    // 添加到一级缓存中
                    addSingleton(beanName, singletonObject);
                }
            }
            return singletonObject;
        }
    }

    protected void addSingleton(String beanName, Object singletonObject) {
        synchronized (this.singletonObjects) {
            // 添加到一级缓存
            this.singletonObjects.put(beanName, singletonObject);
            // 删除对应的二三级缓存
            this.singletonFactories.remove(beanName);
            this.earlySingletonObjects.remove(beanName);
            this.registeredSingletons.add(beanName);
        }
    }

    ......
}
```

上述代码重点关注`singletonFactory.getObject()`，`singletonFactory`是一个函数式接口，对应`AbstractBeanFactory`的`doGetBean`方法中的 lambda 表达式：

```java org.springframework.beans.factory.support.AbstractBeanFactory#doGetBean
sharedInstance = getSingleton(beanName, () -> {
    try {
        // 创建Bean实例
        return createBean(beanName, mbd, args);
    }
    catch (BeansException ex) {
        ......
    }
});
```

其内通过调用`createBean`方法创建 Bean 实例。该方法为抽象方法，由`AbstractBeanFactory`子类`AbstractAutowireCapableBeanFactory`实现。

### `createBean`

```java org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory.java
public abstract class AbstractAutowireCapableBeanFactory extends AbstractBeanFactory
        implements AutowireCapableBeanFactory {

    ......

    @Override
    protected Object createBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
            throws BeanCreationException {
        ......
        try {
            // 创建Bean实例
            Object beanInstance = doCreateBean(beanName, mbdToUse, args);
            return beanInstance;
        }
        catch (BeanCreationException | ImplicitlyAppearedSingletonException ex) {
            throw ex;
        }
        catch (Throwable ex) {
            ......
        }
    }

    protected Object doCreateBean(String beanName, RootBeanDefinition mbd, @Nullable Object[] args)
            throws BeanCreationException {

        BeanWrapper instanceWrapper = null;

        ......
        // 实例化Bean
        if (instanceWrapper == null) {
            instanceWrapper = createBeanInstance(beanName, mbd, args);
        }
        Object bean = instanceWrapper.getWrappedInstance();

        ......

        synchronized (mbd.postProcessingLock) {
            if (!mbd.postProcessed) {
                try {
                    // 执行MergedBeanDefinitionPostProcessor类型后置处理器
                    applyMergedBeanDefinitionPostProcessors(mbd, beanType, beanName);
                }
                catch (Throwable ex) {
                    ......
                }
                mbd.postProcessed = true;
            }
        }

        // 如果该Bean是单例，并且allowCircularReferences属性为true（标识允许循环依赖的出现）以及该Bean正在创建中，
        // earlySingletonExposure就为true，标识允许单例Bean提前暴露原始对象引用（仅实例化）
        boolean earlySingletonExposure = (mbd.isSingleton() && this.allowCircularReferences &&
                isSingletonCurrentlyInCreation(beanName));
        if (earlySingletonExposure) {
            // 添加到单实例工厂集合中（即三级缓存），该方法第二个参数类型为ObjectFactory<?> singletonFactory，
            // 前面提到过它是一个函数式接口，这里用lambda表达式() -> getEarlyBeanReference(beanName, mbd, bean)表示
            addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, mbd, bean));
        }

        Object exposedObject = bean;
        try {
            // 属性赋值操作
            populateBean(beanName, mbd, instanceWrapper);
            // 初始化Bean（初始化操作主要包括 执行XxxAware注入，BeanPostProcessor初始化前/后置处理
            // 及执行InitializingBean或自定义初始化方法）
            exposedObject = initializeBean(beanName, exposedObject, mbd);
        }
        catch (Throwable ex) {
            ......
        }

        // 如果earlySingletonExposure为true
        if (earlySingletonExposure) {
            // 第二个参数为false表示仅从一级和二级缓存中获取Bean实例
            Object earlySingletonReference = getSingleton(beanName, false);
            if (earlySingletonReference != null) {
                if (exposedObject == bean) {
                    // 如果从一级和二级缓存中获取Bean实例不为空，并且exposedObject == bean的话，
                    // 将earlySingletonReference赋值给exposedObject返回
                    exposedObject = earlySingletonReference;
                }
                ......
            }
        }

        ......
        // 返回最终Bean实例
        return exposedObject;
    }

    ......

    protected Object getEarlyBeanReference(String beanName, RootBeanDefinition mbd, Object bean) {
        Object exposedObject = bean;
        if (!mbd.isSynthetic() && hasInstantiationAwareBeanPostProcessors()) {
            // SmartInstantiationAwareBeanPostProcessor类型后置处理，常见的场景为AOP代理
            for (SmartInstantiationAwareBeanPostProcessor bp : getBeanPostProcessorCache().smartInstantiationAware) {
                exposedObject = bp.getEarlyBeanReference(exposedObject, beanName);
            }
        }
        return exposedObject;
    }
}
```

光看源码有点抽象，下面我们通过一个示例来加深理解。

### 普通单例 Bean 间循环依赖

新建 SpringBoot 项目，`pom.xml`引入如下依赖：

```pom.xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter</artifactId>
    </dependency>
</dependencies>
```

新建`CircularRefTest`类：

```java CircularRefTest.java
public class CircularReferenceTest {

    public static void main(String[] args) {
        AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext(BeanA.class, BeanB.class);
        BeanA beanA = context.getBean(BeanA.class);
        BeanB beanB = context.getBean(BeanB.class);
        BeanB beanBInBeanA = beanA.getBeanB();
        BeanA beanAInBeanB = beanB.getBeanA();
        System.out.println(beanA);
        System.out.println(beanB);
        System.out.println(beanB == beanBInBeanA);
        System.out.println(beanA == beanAInBeanB);
    }
}

class BeanA {

    @Autowired
    private BeanB beanB;

    public BeanB getBeanB() {
        return beanB;
    }

    public void setBeanB(BeanB beanB) {
        this.beanB = beanB;
    }
}

class BeanB {

    @Autowired
    private BeanA beanA;

    public BeanA getBeanA() {
        return beanA;
    }

    public void setBeanA(BeanA beanA) {
        this.beanA = beanA;
    }
}
```

上面代码通过`AnnotationConfigApplicationContext`创建了 IOC 容器，并先后注册了相互依赖的`BeanA`和`BeanB`，程序输出如下：

```
com.example.BeanA@f4168b8
com.example.BeanB@3bd94634
true
true
```

#### 原理剖析

{% asset_img CircularRefTest.png getBean(BeanA.class)序列图%}

上面的例子是基于属性注入的情况，假如存在构造器注入情况下的循环依赖，Spring 将没办法解决。这是因为对象的提前曝光时机发生在对象实例化之后，而构造器注入时机为对象实例化时，所以此时还未进行提前曝光操作，循环依赖也就没办法解决了。
