---
title: Spring AOP原理
date: 2023-11-05 21:31:11
categories:
  - [JAVA, Spring]
tags:
  - spring
  - spring core
---

## Spring AOP 原理

### AOP 概念

AOP(Aspect Oriented Programming)是一种面向切面的编程思想，是面向对象（OOP）编程的一种补充和完善。它通过预编译和运行期动态代理，实现在不修改源代码的情况下给程序动态统一的添加额外的功能。

- 切面（`Aspect`）：切面将多个类的通用行为封装成可重用的模块，该模块含有一组 API 提供横切功能。
- 连接点（`JoinPoint`）：连接点表示切面将会被织入到目标对象的哪个位置。
- 切入点（`Pointcut`）：切入点是一个或一组连接点，通知将在这些位置执行。可以通过切点表达式指明。
- 通知（`Advice`）：通知包括以下几种类型待织入到目标类中的切面代码。
  - 前置通知（Before）：在连接点之前执行。
  - 环绕通知（Around）：在连接点之前和之后执行。
  - 返回通知（After Returning）：在连接点正常返回后执行。
  - 异常通知（After Throwing）：在连接点抛出异常后执行。
  - 后置通知（After）：在连接点之后执行（不管是正常返回还是抛出异常）。
- 织入（`Weaving`）：织入是将切面代码编织到目标对象中的过程，可以发生在编译时、加载时或运行时。Spring AOP 以动态代理技术为主进行织入。
- 引入（`Introduction`）：引入允许我们在已存在的类中增加新的方法和属性。

<!-- more -->

### 示例代码

新建 SpringBoot 2.2.4.RELEASE 项目，`pom.xml`引入如下依赖：

```pom.xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-aop</artifactId>
    </dependency>
</dependencies>
```

新建`TatgetBean`类：

```java TargetBean.java
@Component
public class TargetBean {

    public String test(String value) {
        System.out.println("invoke test...");
        if (!StringUtils.hasLength(value)) {
            throw new IllegalArgumentException("value cannot be empty");
        }
        return value;
    }
}
```

新建`TatgetBeanAspect`切面类：

```java TatgetBeanAspect.java
@Aspect
@Component
public class TargetBeanAspect {

    @Pointcut("execution(public * com.example..*.TargetBean.test(..))")
    public void pointcut() {
    }

    @Before("pointcut()")
    public void onBefore(JoinPoint joinPoint) {
        System.out.println("onBefore：" + joinPoint.getSignature().getName() + " args:"
                + Arrays.asList(joinPoint.getArgs()));
    }

    @After("pointcut()")
    public void onAfter(JoinPoint joinPoint) {
        System.out.println("onAfter：" + joinPoint.getSignature().getName() + " args:"
                + Arrays.asList(joinPoint.getArgs()));
    }

    @AfterReturning(value = "pointcut()", returning = "result")
    public void afterReturning(JoinPoint joinPoint, Object result) {
        System.out.println("afterReturning：" + joinPoint.getSignature().getName() + " args:"
                + Arrays.asList(joinPoint.getArgs()) + " result:" + result);
    }

    @AfterThrowing(value = "pointcut()", throwing = "exception")
    public void afterThrowing(JoinPoint joinPoint, Exception exception) {
        System.out.println("afterThrowing：" + joinPoint.getSignature().getName() + " args:"
                + Arrays.asList(joinPoint.getArgs()) + " exception:" + exception);
    }
}
```

这几个通知的执行顺序如下：

- 正常情况：`@Before` —> 目标方法 —> `@After` —> `@AfterReturning`
- 异常情况：`@Before` —> 目标方法 —> `@After` —> `@AfterThrowing`

新建`DemoApplication`测试类：

```java DemoApplication.java
@SpringBootApplication
public class DemoApplication {

    public static void main(String[] args) {
        ConfigurableApplicationContext context = SpringApplication.run(DemoApplication.class, args);
        TargetBean bean = context.getBean(TargetBean.class);
        bean.test("ok"); // 正常情况
        bean.test(""); // 异常情况
    }
}
```

程序运行结果如下：

```
onBefore：test args:[ok]
invoke test...
onAfter：test args:[ok]
afterReturning：test args:[ok] result:ok

onBefore：test args:[]
invoke test...
onAfter：test args:[]
Exception in thread "main" afterThrowing：test args:[] exception:java.lang.IllegalArgumentException: value cannot be empty
java.lang.IllegalArgumentException: value cannot be empty
......
```

可以看到结果符合预期，Spring AOP 成功将各个通知方法织入到了目标方法的各个执行阶段。

### 创建代理对象

#### `@EnableAspectJAutoProxy`

上述示例中引入了 Spring Boot 中开箱即用的`spring-boot-starter-aop`，`@EnableAspectJAutoProxy` 注解用于开启 AspectJ 自动代理，源码如下：

```java org.springframework.context.annotation.EnableAspectJAutoProxy.java
@Target({ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Import({AspectJAutoProxyRegistrar.class})
public @interface EnableAspectJAutoProxy {

    boolean proxyTargetClass() default false;

    boolean exposeProxy() default false;
}
```

该注解类上通过`@Import`导入了`AspectJAutoProxyRegistrarAspectJ`自动代理注册器。

```java org.springframework.context.annotation.AspectJAutoProxyRegistrar.java
class AspectJAutoProxyRegistrar implements ImportBeanDefinitionRegistrar {

    /**
     * Register, escalate, and configure the AspectJ auto proxy creator based on the value
     * of the @{@link EnableAspectJAutoProxy#proxyTargetClass()} attribute on the importing
     * {@code @Configuration} class.
     */
    @Override
    public void registerBeanDefinitions(
            AnnotationMetadata importingClassMetadata, BeanDefinitionRegistry registry) {
        // 注册AnnotationAwareAspectJAutoProxyCreator
        AopConfigUtils.registerAspectJAnnotationAutoProxyCreatorIfNecessary(registry);

        AnnotationAttributes enableAspectJAutoProxy =
                AnnotationConfigUtils.attributesFor(importingClassMetadata, EnableAspectJAutoProxy.class);
        if (enableAspectJAutoProxy != null) { // 配置属性值
            if (enableAspectJAutoProxy.getBoolean("proxyTargetClass")) {
                AopConfigUtils.forceAutoProxyCreatorToUseClassProxying(registry);
            }
            if (enableAspectJAutoProxy.getBoolean("exposeProxy")) {
                AopConfigUtils.forceAutoProxyCreatorToExposeProxy(registry);
            }
        }
    }
}
```

该注册器的作用是往 IOC 容器里注册了一个类型为`AnnotationAwareAspectJAutoProxyCreator`的 Bean，其名称为`org.springframework.aop.config.internalAutoProxyCreator`。

```java org.springframework.aop.config.AopConfigUtils.java
public abstract class AopConfigUtils {

    ......

    @Nullable
    public static BeanDefinition registerAspectJAnnotationAutoProxyCreatorIfNecessary(BeanDefinitionRegistry registry) {
        return registerAspectJAnnotationAutoProxyCreatorIfNecessary(registry, null);
    }

    @Nullable
    public static BeanDefinition registerAspectJAnnotationAutoProxyCreatorIfNecessary(
            BeanDefinitionRegistry registry, @Nullable Object source) {
        return registerOrEscalateApcAsRequired(AnnotationAwareAspectJAutoProxyCreator.class, registry, source);
    }

    @Nullable
    private static BeanDefinition registerOrEscalateApcAsRequired(
            Class<?> cls, BeanDefinitionRegistry registry, @Nullable Object source) {
        Assert.notNull(registry, "BeanDefinitionRegistry must not be null");

        // 判断容器中是否包含org.springframework.aop.config.internalAutoProxyCreator bean
        if (registry.containsBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME)) {
            BeanDefinition apcDefinition = registry.getBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME);
            if (!cls.getName().equals(apcDefinition.getBeanClassName())) {
                int currentPriority = findPriorityForClass(apcDefinition.getBeanClassName());
                int requiredPriority = findPriorityForClass(cls);
                // 若已包含但优先级较低，则重置Bean类名
                if (currentPriority < requiredPriority) {
                    apcDefinition.setBeanClassName(cls.getName());
                }
            }
            return null;
        }

        // 不包含则通过RootBeanDefinition注册一个 AnnotationAwareAspectJAutoProxyCreator bean
        RootBeanDefinition beanDefinition = new RootBeanDefinition(cls);
        beanDefinition.setSource(source);
        beanDefinition.getPropertyValues().add("order", Ordered.HIGHEST_PRECEDENCE);
        beanDefinition.setRole(BeanDefinition.ROLE_INFRASTRUCTURE);
        registry.registerBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME, beanDefinition);
        return beanDefinition;
    }

    ......
}
```

#### `AnnotationAwareAspectJAutoProxyCreator`

通过前面的分析，得知核心在`AnnotationAwareAspectJAutoProxyCreator`类上，其层级结构如下：

{% asset_img AnnotationAwareAspectJAutoProxyCreator.png %}

可以看到`AnnotationAwareAspectJAutoProxyCreator`的祖先类`AbstractAutoProxyCreator`实现了`SmartInstantiationAwareBeanPostProcessor`和`BeanFactoryAware`接口。

实现`BeanFactoryAware`用于在 Bean 初始化时注入`BeanFactory`，而`SmartInstantiationAwareBeanPostProcessor`的父接口为 `InstantiationAwareBeanPostProcessor`，该接口又继承自`BeanPostProcessor`接口。这两个接口的作用如下所述。

##### `BeanPostProcessor`

- `postProcessBeforeInitialization`：方法将在 Bean 实例的`afterPropertiesSet`方法或者自定义的`init`方法被**调用前**调用，此时 Bean 属性已经被赋值。方法返回原始 Bean 实例或者包装后的 Bean 实例，如果返回`null`，则后续的后置处理方法不再被调用。
- `postProcessAfterInitialization`：方法将在 Bean 实例的`afterPropertiesSet`方法或者自定义的`init`方法被**调用后**调用，此时 Bean 属性已经被赋值。方法返回原始 Bean 实例或者包装后的 Bean 实例，如果返回`null`，则后续的后置处理方法不再被调用。

##### `InstantiationAwareBeanPostProcessor`

- `postProcessBeforeInstantiation`：在 Bean **实例化前**调用该方法，返回值可以为代理后的 Bean，以此代替 Bean 默认的实例化过程。如果返回`null`，继续默认实例化。
- `postProcessAfterInstantiation`：当 Bean 通过构造器或者工厂方法被**实例化后**，当属性还未被赋值前，该方法会被调用，一般用于自定义属性赋值。方法返回值为布尔类型，返回`true`时，表示 Bean 属性需要被赋值；返回`false`表示跳过 Bean 属性赋值。
- `postProcessProperties`：在 Bean 工厂将给定的属性值应用于给定的 Bean 之前，对其进行后处理，该方法不需要任何属性描述符。如果返回`null`，继续调用`postProcessPropertyValues`；否则返回工厂即将应用的所有属性值。
- `postProcessPropertyValues`：与`postProcessProperties`方法不同的是，该方法多了参数属性描述符`PropertyDescriptor[]`。它允许检查是否满足了所有依赖项，例如基于 Bean 属性设置器上的`@Required`注解；还允许替换将要应用的属性值，通常是基于原始 `PropertyValues`实例创建新的`MutablePropertyValues`实例，添加或删除特定值。

> `Initialization`为初始化，`Instantiation`为实例化。在 Spring Bean 生命周期中，实例化指的是创建 Bean 的过程，初始化指的是 Bean 创建后，对其属性进行赋值、后置处理等操作的过程，所以实例化执行时机先于初始化。

`AbstractAutoProxyCreator`类实现了`InstantiationAwareBeanPostProcessor`接口的`postProcessBeforeInstantiation`方法（自定义 Bean 实例化前置逻辑），实现了`BeanPostProcessor`的`postProcessAfterInitialization`方法（自定义 Bean 初始化后置逻辑）

```java org.springframework.aop.framework.autoproxy.AbstractAutoProxyCreator.java
public abstract class AbstractAutoProxyCreator extends ProxyProcessorSupport
        implements SmartInstantiationAwareBeanPostProcessor, BeanFactoryAware {

    // 用于存放所有Bean是否需要增强标识，键为每个Bean的cacheKey，值为布尔类型
    private final Map<Object, Boolean> advisedBeans = new ConcurrentHashMap<>(256);

    ......

    @Override
    public Object postProcessBeforeInstantiation(Class<?> beanClass, String beanName) {
        // 通过Bean名称和Bean类型获取该Bean的唯一缓存键名
        Object cacheKey = getCacheKey(beanClass, beanName);

        if (!StringUtils.hasLength(beanName) || !this.targetSourcedBeans.contains(beanName)) {
            // 判断当前Bean是否包含在advisedBeans集合中
            if (this.advisedBeans.containsKey(cacheKey)) {
                return null;
            }
            // 判断当前Bean是否是基础设施类 || 给定的Bean名称是否表示原始实例(以.ORIGINAL结尾)
            if (isInfrastructureClass(beanClass) || shouldSkip(beanClass, beanName)) {
                this.advisedBeans.put(cacheKey, Boolean.FALSE);
                return null;
            }
        }

        // 如果我们有自定义 TargetSource，会在此处创建代理
        // 抑制目标Bean不必要的默认实例化：TargetSource 将以自定义方式处理目标实例
        TargetSource targetSource = getCustomTargetSource(beanClass, beanName);
        if (targetSource != null) {
            if (StringUtils.hasLength(beanName)) {
                this.targetSourcedBeans.add(beanName);
            }
            Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(beanClass, beanName, targetSource);
            Object proxy = createProxy(beanClass, beanName, specificInterceptors, targetSource);
            this.proxyTypes.put(cacheKey, proxy.getClass());
            return proxy;
        }

        return null; // 可以看出我们的TargetBean均不满足以上case，返回了null
    }

    @Override
    public boolean postProcessAfterInstantiation(Object bean, String beanName) {
        return true;
    }

    @Override
    public PropertyValues postProcessProperties(PropertyValues pvs, Object bean, String beanName) {
        return pvs;
    }

    @Override
    public Object postProcessBeforeInitialization(Object bean, String beanName) {
        return bean;
    }

    /**
     * 如果该Bean被子类识别为需要代理的Bean，则使用配置的拦截器创建一个代理。
     */
    @Override
    public Object postProcessAfterInitialization(@Nullable Object bean, String beanName) {
        if (bean != null) {
            Object cacheKey = getCacheKey(bean.getClass(), beanName);
            // 此处null != TargetBean，因此执行wrapIfNecessary
            if (this.earlyProxyReferences.remove(cacheKey) != bean) {
                return wrapIfNecessary(bean, beanName, cacheKey);
            }
        }
        return bean;
    }

    protected Object wrapIfNecessary(Object bean, String beanName, Object cacheKey) {
        if (StringUtils.hasLength(beanName) && this.targetSourcedBeans.contains(beanName)) {
            return bean;
        }
        if (Boolean.FALSE.equals(this.advisedBeans.get(cacheKey))) {
            return bean;
        }
        if (isInfrastructureClass(bean.getClass()) || shouldSkip(bean.getClass(), beanName)) {
            this.advisedBeans.put(cacheKey, Boolean.FALSE);
            return bean;
        }

        // 获取该Bean对应的通知方法集合
        Object[] specificInterceptors = getAdvicesAndAdvisorsForBean(bean.getClass(), beanName, null);
        if (specificInterceptors != DO_NOT_PROXY) {
            this.advisedBeans.put(cacheKey, Boolean.TRUE);
            // 如果该Bean的通知方法集合不为空的话，则创建该Bean的代理对象
            Object proxy = createProxy(
                    bean.getClass(), beanName, specificInterceptors, new SingletonTargetSource(bean));
            this.proxyTypes.put(cacheKey, proxy.getClass());
            return proxy;
        }

        this.advisedBeans.put(cacheKey, Boolean.FALSE);
        return bean;
    }

    /**
     * 判断当前Bean是否是Advice，Pointcut，Advisor，AopInfrastructureBean的子类
     * AnnotationAwareAspectJAutoProxyCreator子类重写了该方法，增加了是否为切面类（@Aspect注解标注）判断
     */
    protected boolean isInfrastructureClass(Class<?> beanClass) {
        boolean retVal = Advice.class.isAssignableFrom(beanClass) ||
                Pointcut.class.isAssignableFrom(beanClass) ||
                Advisor.class.isAssignableFrom(beanClass) ||
                AopInfrastructureBean.class.isAssignableFrom(beanClass);
        if (retVal && logger.isTraceEnabled()) {
            logger.trace("Did not attempt to auto-proxy infrastructure class [" + beanClass.getName() + "]");
        }
        return retVal;
    }

    protected Object createProxy(Class<?> beanClass, @Nullable String beanName,
            @Nullable Object[] specificInterceptors, TargetSource targetSource) {

        if (this.beanFactory instanceof ConfigurableListableBeanFactory) {
            AutoProxyUtils.exposeTargetClass((ConfigurableListableBeanFactory) this.beanFactory, beanName, beanClass);
        }

        ProxyFactory proxyFactory = new ProxyFactory();
        proxyFactory.copyFrom(this);

        if (!proxyFactory.isProxyTargetClass()) {
            if (shouldProxyTargetClass(beanClass, beanName)) {
                proxyFactory.setProxyTargetClass(true);
            }
            else {
                evaluateProxyInterfaces(beanClass, proxyFactory);
            }
        }

        // 将specificInterceptors包装未Advisor类型数组
        Advisor[] advisors = buildAdvisors(beanName, specificInterceptors);
        proxyFactory.addAdvisors(advisors); // 保存到代理工厂中
        proxyFactory.setTargetSource(targetSource); // 设置目标代理对象
        customizeProxyFactory(proxyFactory);

        proxyFactory.setFrozen(this.freezeProxy);
        if (advisorsPreFiltered()) {
            proxyFactory.setPreFiltered(true);
        }
        // 代理工厂创建代理对象
        return proxyFactory.getProxy(getProxyClassLoader());
    }
    ......
}
```

`getAdvicesAndAdvisorsForBean`方法内部主要包含以下逻辑：

```java org.springframework.aop.framework.autoproxy.AbstractAdvisorAutoProxyCreator.java
public abstract class AbstractAdvisorAutoProxyCreator extends AbstractAutoProxyCreator {
    ......

    @Override
    @Nullable
    protected Object[] getAdvicesAndAdvisorsForBean(
            Class<?> beanClass, String beanName, @Nullable TargetSource targetSource) {

        List<Advisor> advisors = findEligibleAdvisors(beanClass, beanName);
        if (advisors.isEmpty()) {
            return DO_NOT_PROXY;
        }
        return advisors.toArray();
    }

    protected List<Advisor> findEligibleAdvisors(Class<?> beanClass, String beanName) {
        // 获取所有的通知方法（切面里定义的各个通知方法）
        List<Advisor> candidateAdvisors = findCandidateAdvisors();
        // 通过切点表达式判断这些通知方法是否可为当前Bean所用
        List<Advisor> eligibleAdvisors = findAdvisorsThatCanApply(candidateAdvisors, beanClass, beanName);
        // 如果启用AspectJ，会增加一个特殊的通知（ExposeInvocationInterceptor.ADVISOR）
        extendAdvisors(eligibleAdvisors);
        // 如果有符合的通知方法，则对它们进行排序
        if (!eligibleAdvisors.isEmpty()) {
            eligibleAdvisors = sortAdvisors(eligibleAdvisors);
        }
        return eligibleAdvisors;
    }

    ......
}
```

对于我们的示例`TargetBean`而言，`getAdvicesAndAdvisorsForBean`方法返回值如下所示：

{% asset_img getAdvicesAndAdvisorsForBean.png %}

这些通知方法就是我们在`TargetBeanAspect`切面里定义的通知方法和附加的`ExposeInvocationInterceptor.ADVISOR`。

如果该 Bean 的通知方法集合不为空的话，则通过`ProxyFactory`创建该 Bean 的代理对象，具体查看如下源码：

```java org.springframework.aop.framework.ProxyFactory.java
public class ProxyFactory extends ProxyCreatorSupport {

    ......
    public Object getProxy(@Nullable ClassLoader classLoader) {
        return createAopProxy().getProxy(classLoader);
    }
    ......
}
```

```java org.springframework.aop.framework.ProxyCreatorSupport.java
public class ProxyCreatorSupport extends AdvisedSupport {

    ......
    protected final synchronized AopProxy createAopProxy() {
        if (!this.active) {
            activate();
        }
        return getAopProxyFactory().createAopProxy(this);
    }
    ......
}
```

```java org.springframework.aop.framework.DefaultAopProxyFactory.java
public class DefaultAopProxyFactory implements AopProxyFactory, Serializable {

    @Override
    public AopProxy createAopProxy(AdvisedSupport config) throws AopConfigException {
        // isOptimize(): 默认false，是否考虑优先采用Cglib，因为Cglib的性能高于JDK的Proxy
        // isProxyTargetClass(): 默认false，是否基于类的代理
        // hasNoUserSuppliedProxyInterfaces: 根据被代理类的接口判断，如果未实现任何接口，那么也采用Cglib
        if (config.isOptimize() || config.isProxyTargetClass() || hasNoUserSuppliedProxyInterfaces(config)) {
            Class<?> targetClass = config.getTargetClass();
            if (targetClass == null) {
                throw new AopConfigException("TargetSource cannot determine target class: " +
                        "Either an interface or a target is required for proxy creation.");
            }
            // 当前类是接口 或者 是java.lang.reflect.Proxy JDK代理类
            if (targetClass.isInterface() || Proxy.isProxyClass(targetClass)) {
                return new JdkDynamicAopProxy(config); // 使用jdk动态代理
            }
            return new ObjenesisCglibAopProxy(config); // 使用cglib动态代理
        }
        else {
            return new JdkDynamicAopProxy(config);
        }
    }

    /**
     * Determine whether the supplied {@link AdvisedSupport} has only the
     * {@link org.springframework.aop.SpringProxy} interface specified
     * (or no proxy interfaces specified at all).
     */
    private boolean hasNoUserSuppliedProxyInterfaces(AdvisedSupport config) {
        Class<?>[] ifcs = config.getProxiedInterfaces();
        return (ifcs.length == 0 || (ifcs.length == 1 && SpringProxy.class.isAssignableFrom(ifcs[0])));
    }
}
```

后续从 IOC 容器中获得的`TargetBean`就是被代理后的对象，执行代理对象的目标方法的时候，代理对象会执行相应的通知方法链。

### 构建拦截器链

AOP 代理对象生成后，我们继续关注代理对象的目标方法执行时，通知方法是怎么被执行的。

首先在入口类`DemoApplication`的如下位置打个断点，以 debug 方式启动程序：

{% asset_img DemoApplication.png %}

可以看到获取到的`TargetBean`就是前面 cglib 代理后的 Bean（`TargetBean$$EnhanceBySpringCGLIB$$1bb9151e@3284`）。点击 Step Into 进入`test`方法内部调用逻辑，会发现程序跳转到了`CglibAopProxy$DynamicAdvisedInterceptor`的`intercept`方法中。也就是需要我们重点关注的`CGLIB$CALLBACK_0`：

```java org.springframework.aop.framework.CglibAopProxy.DynamicAdvisedInterceptor.java
private static class DynamicAdvisedInterceptor implements MethodInterceptor, Serializable {

    private final AdvisedSupport advised;

    public DynamicAdvisedInterceptor(AdvisedSupport advised) {
        this.advised = advised;
    }

    @Override
    @Nullable
    public Object intercept(Object proxy, Method method, Object[] args, MethodProxy methodProxy)
        throws Throwable {
        Object oldProxy = null;
        boolean setProxyContext = false;
        Object target = null;
        TargetSource targetSource = this.advised.getTargetSource();
        try {
            // 若配置了exposeProxy=true，则暴露当前代理对象到线程上下文
            if (this.advised.exposeProxy) {
                oldProxy = AopContext.setCurrentProxy(proxy);
                setProxyContext = true;
            }
            // Get as late as possible to minimize the time we "own" the target, in case it comes from a pool...
            target = targetSource.getTarget();
            Class<?> targetClass = (target != null ? target.getClass() : null);
            // 获取目标对象目标方法的拦截器链
            List<Object> chain = this.advised.getInterceptorsAndDynamicInterceptionAdvice(method, targetClass);
            Object retVal;
            // 如果无拦截器链，直接通过反射执行目标方法
            if (chain.isEmpty() && Modifier.isPublic(method.getModifiers())) {
                // We can skip creating a MethodInvocation: just invoke the target directly.
                // Note that the final invoker must be an InvokerInterceptor, so we know
                // it does nothing but a reflective operation on the target, and no hot
                // swapping or fancy proxying.
                Object[] argsToUse = AopProxyUtils.adaptArgumentsIfNecessary(method, args);
                retVal = methodProxy.invoke(target, argsToUse);
            }
            else {
                // 否则需要创建一个CglibMethodInvocation对象，执行它的proceed方法
                retVal = new CglibMethodInvocation(proxy, target, method, args, targetClass, chain, methodProxy).proceed();
            }
            retVal = processReturnType(proxy, target, method, retVal);
            return retVal;
        }
        finally {
            if (target != null && !targetSource.isStatic()) {
                targetSource.releaseTarget(target);
            }
            if (setProxyContext) {
                // Restore old proxy.
                AopContext.setCurrentProxy(oldProxy);
            }
        }
    }
    ......
}
```

这里先将目光聚焦到`getInterceptorsAndDynamicInterceptionAdvice`方法，其源码如下所示：

```java org.springframework.aop.framework.AdvisedSupport.java
public class AdvisedSupport extends ProxyConfig implements Advised {

    ......
    public List<Object> getInterceptorsAndDynamicInterceptionAdvice(Method method, @Nullable Class<?> targetClass) {
        // 创建目标方法的缓存键
        MethodCacheKey cacheKey = new MethodCacheKey(method);
        List<Object> cached = this.methodCache.get(cacheKey);
        if (cached == null) {
            // 如果无缓存则获取拦截器链并缓存
            cached = this.advisorChainFactory.getInterceptorsAndDynamicInterceptionAdvice(
                    this, method, targetClass);
            this.methodCache.put(cacheKey, cached);
        }
        return cached;
    }
    ......
}
```

```java org.springframework.aop.framework.DefaultAdvisorChainFactory.java
public class DefaultAdvisorChainFactory implements AdvisorChainFactory, Serializable {

    @Override
    public List<Object> getInterceptorsAndDynamicInterceptionAdvice(
            Advised config, Method method, @Nullable Class<?> targetClass) {
        AdvisorAdapterRegistry registry = GlobalAdvisorAdapterRegistry.getInstance();
        // 获取Advisor列表
        Advisor[] advisors = config.getAdvisors();
        List<Object> interceptorList = new ArrayList<>(advisors.length);
        Class<?> actualClass = (targetClass != null ? targetClass : method.getDeclaringClass());
        Boolean hasIntroductions = null;

        for (Advisor advisor : advisors) {
            if (advisor instanceof PointcutAdvisor) {
                // 如果是PointcutAdvisor实例，仅代理通过类型匹配和方法匹配的方法
                PointcutAdvisor pointcutAdvisor = (PointcutAdvisor) advisor;
                // 若已预过滤过，或进行类匹配检查通过
                if (config.isPreFiltered() || pointcutAdvisor.getPointcut().getClassFilter().matches(actualClass)) {
                    // 再进行方法匹配检查
                    MethodMatcher mm = pointcutAdvisor.getPointcut().getMethodMatcher();
                    boolean match;
                    if (mm instanceof IntroductionAwareMethodMatcher) {
                        if (hasIntroductions == null) {
                            hasIntroductions = hasMatchingIntroductions(advisors, actualClass);
                        }
                        match = ((IntroductionAwareMethodMatcher) mm).matches(method, actualClass, hasIntroductions);
                    }
                    else {
                        match = mm.matches(method, actualClass);
                    }
                    if (match) {
                        // 切点匹配，则通过注册器将Advisor通知适配成MethodInterceptor数组
                        MethodInterceptor[] interceptors = registry.getInterceptors(advisor);
                        if (mm.isRuntime()) {
                            // Creating a new object instance in the getInterceptors() method
                            // isn't a problem as we normally cache created chains.
                            for (MethodInterceptor interceptor : interceptors) {
                                interceptorList.add(new InterceptorAndDynamicMethodMatcher(interceptor, mm));
                            }
                        }
                        else {
                            interceptorList.addAll(Arrays.asList(interceptors));
                        }
                    }
                }
            }
            // 如果是IntroductionAdvisor实例，通过类型匹配之后，接口所有的方法都要代理
            else if (advisor instanceof IntroductionAdvisor) {
                IntroductionAdvisor ia = (IntroductionAdvisor) advisor;
                if (config.isPreFiltered() || ia.getClassFilter().matches(actualClass)) {
                    Interceptor[] interceptors = registry.getInterceptors(advisor);
                    interceptorList.addAll(Arrays.asList(interceptors));
                }
            }
            else { // 如果是普通的 Advisor
                Interceptor[] interceptors = registry.getInterceptors(advisor);
                interceptorList.addAll(Arrays.asList(interceptors));
            }
        }

        return interceptorList;
    }

    /**
     * Determine whether the Advisors contain matching introductions.
     */
    private static boolean hasMatchingIntroductions(Advisor[] advisors, Class<?> actualClass) {
        for (Advisor advisor : advisors) {
            if (advisor instanceof IntroductionAdvisor) {
                IntroductionAdvisor ia = (IntroductionAdvisor) advisor;
                if (ia.getClassFilter().matches(actualClass)) {
                    return true;
                }
            }
        }
        return false;
    }
}
```

通过 debug 我们可以看到，当前代理对象的`test`方法的拦截器链不为空，并且有 5 个元素：

{% asset_img getInterceptorsAndDynamicInterceptionAdvice.png 拦截器链%}

拦截器链第一个元素类型为`ExposeInvocationInterceptor`，是默认的拦截器。剩下四个依次为：`AspectJAfterThrowingAdvice`、`AfterReturningAdviceInterceptor`、`AspectJAfterAdvice`和`MethodBeforeAdviceInterceptor`，它们都是`MethodInterceptor`的实现类：

{% asset_img MethodInterceptor.png %}

### 链式调用通知方法

最后我们关注下这些拦截器是如何链式调用通知方法的。继续从`CglibMethodInvocation.proceed()`debug：

```java org.springframework.aop.framework.CglibAopProxy.CglibMethodInvocation.java
private static class CglibMethodInvocation extends ReflectiveMethodInvocation {

        @Nullable
        private final MethodProxy methodProxy;

        public CglibMethodInvocation(Object proxy, @Nullable Object target, Method method,
                Object[] arguments, @Nullable Class<?> targetClass,
                List<Object> interceptorsAndDynamicMethodMatchers, MethodProxy methodProxy) {
            //  代理对象 目标对象 目标方法 目标方法参数 目标对象类   拦截器链
            super(proxy, target, method, arguments, targetClass, interceptorsAndDynamicMethodMatchers);

            // 仅对不是从 java.lang.Object 派生的公共方法使用方法代理
            this.methodProxy = (Modifier.isPublic(method.getModifiers()) &&
                    method.getDeclaringClass() != Object.class && !AopUtils.isEqualsMethod(method) &&
                    !AopUtils.isHashCodeMethod(method) && !AopUtils.isToStringMethod(method) ?
                    methodProxy : null);
        }

        @Override
        @Nullable
        public Object proceed() throws Throwable {
            try {
                return super.proceed(); // 调用父类proceed()
            }
            catch (RuntimeException ex) {
                throw ex;
            }
            catch (Exception ex) {
                if (ReflectionUtils.declaresException(getMethod(), ex.getClass())) {
                    throw ex;
                }
                else {
                    throw new UndeclaredThrowableException(ex);
                }
            }
        }

        @Override
        protected Object invokeJoinpoint() throws Throwable {
            if (this.methodProxy != null) {
                return this.methodProxy.invoke(this.target, this.arguments);
            }
            else {
                return super.invokeJoinpoint();
            }
        }
    }
```

查看`CglibMethodInvocation`父类`ReflectiveMethodInvocation` `proceed`方法源码：

#### `ReflectiveMethodInvocation`

```java org.springframework.aop.framework.ReflectiveMethodInvocation.java
public class ReflectiveMethodInvocation implements ProxyMethodInvocation, Cloneable {
    ......

    @Override
    @Nullable
    public Object proceed() throws Throwable {
        // 我们从索引 -1 开始并提前递增
        if (this.currentInterceptorIndex == this.interceptorsAndDynamicMethodMatchers.size() - 1) {
            return invokeJoinpoint();
        }

        // 获取对应索引位置的拦截器
        Object interceptorOrInterceptionAdvice =
                this.interceptorsAndDynamicMethodMatchers.get(++this.currentInterceptorIndex);
        // 若是一个InterceptorAndDynamicMethodMatcher，则执行拦截器前需要进行方法匹配评估
        if (interceptorOrInterceptionAdvice instanceof InterceptorAndDynamicMethodMatcher) {
            // Evaluate dynamic method matcher here: static part will already have
            // been evaluated and found to match.
            InterceptorAndDynamicMethodMatcher dm =
                    (InterceptorAndDynamicMethodMatcher) interceptorOrInterceptionAdvice;
            Class<?> targetClass = (this.targetClass != null ? this.targetClass : this.method.getDeclaringClass());
            // 动态匹配成功，则执行此拦截器
            if (dm.methodMatcher.matches(this.method, targetClass, this.arguments)) {
                return dm.interceptor.invoke(this);
            }
            else {
                // 动态匹配失败，则跳过此拦截器并调用链中的下一个拦截器
                return proceed();
            }
        }
        else {
            // 若是一个拦截器，则直接需调用它：切点在构造之前已经提前评估过了
            return ((MethodInterceptor) interceptorOrInterceptionAdvice).invoke(this);
        }
    }
    ......
}
```

程序第一次进该方法时`currentInterceptorIndex`值为-1，`this.interceptorsAndDynamicMethodMatchers.get(++this.currentInterceptorIndex)`取出拦截器链第一个拦截器`ExposeInvocationInterceptor`，方法最后调用该拦截器的`invoke`方法，Step Into 进入该方法：

{% asset_img ExposeInvocationInterceptor.png %}

`mi`就是我们传入的`ReflectiveMethodInvocation`对象，程序执行到`mi.proceed`方法时，Step Into 进入该方法。此时`currentInterceptorIndex`值为 0，会取出第二个拦截器`AspectJAfterThrowingAdvice`，继而执行其`invoke`方法：

{% asset_img AspectJAfterThrowingAdvice.png %}

接着又通过`mi.proceed`再次调用`ReflectiveMethodInvocation`的`poceed`方法，Step Into 进入该方法。此时`currentInterceptorIndex`值为 1，会取出第三个拦截器`AfterReturningAdviceInterceptor`，继而执行其`invoke`方法：

{% asset_img AfterReturningAdviceInterceptor.png %}

接着又通过`mi.proceed`再次调用`ReflectiveMethodInvocation`的`poceed`方法，Step Into 进入该方法。此时`currentInterceptorIndex`值为 2，会取出第四个拦截器`AspectJAfterAdvice`，继而执行其`invoke`方法：

{% asset_img AspectJAfterAdvice.png %}

接着又通过`mi.proceed`再次调用`ReflectiveMethodInvocation`的`poceed`方法，Step Into 进入该方法。此时`currentInterceptorIndex`值为 3，会取出第五个拦截器`MethodBeforeAdviceInterceptor`，继而执行其`invoke`方法：

{% asset_img MethodBeforeAdviceInterceptor.png %}

此时会执行前置通知，执行后控制台打印内容如下：

```
onBefore：test args:[ok]
```

随后继续通过`mi.proceed`再次调用`ReflectiveMethodInvocation`的`poceed`方法，Step Into 进入该方法。此时`currentInterceptorIndex`值为 4，而拦截器链的长度为 5，判断成立所以执行`invokeJoinpoint()`方法，该方法内部通过反射调用了目标方法：

{% asset_img ReflectiveMethodInvocation_proceed.png %}

`invokeJoinpoint()`执行后控制台打印内容如下：

```
onBefore：test args:[ok]
invoke test...
```

接着从`MethodBeforeAdviceInterceptor.invoke`方法返回，程序回到`AspectJAfterAdvice.invoke`方法：

{% asset_img AspectJAfterAdvice_invokeAdviceMethod.png %}

继续执行后置通知逻辑，控制台打印内容如下：

```
onBefore：test args:[ok]
invoke test...
onAfter：test args:[ok]
```

`AspectJAfterAdvice.invoke`方法执行结束出栈，程序回到`AfterReturningAdviceInterceptor.invoke`方法：

{% asset_img AfterReturningAdviceInterceptor_afterReturning.png %}

继续执行返回通知逻辑，控制台打印内容如下：

```
onBefore：test args:[ok]
invoke test...
onAfter：test args:[ok]
afterReturning：test args:[ok] result:ok
```

`AfterReturningAdviceInterceptor.invoke`方法执行结束出栈，程序回到`AspectJAfterThrowingAdvice.invoke`方法。此时方法执行未抛出异常，正常返回执行结果。假如方法执行抛出异常则跳过执行`afterReturning`返回通知，转而执行异常通知：

{% asset_img AspectJAfterThrowingAdvice_invokeAdviceMethod.png %}

`AspectJAfterThrowingAdvice.invoke`方法执行结束出栈，程序回到`ExposeInvocationInterceptor.invoke`方法，整个 AOP 的拦截器链调用也随之结束。我们已经成功在目标方法的各个执行时期织入了通知方法。

下面用一张图总结拦截器链调用过程：

{% asset_img spring_aop.png %}
