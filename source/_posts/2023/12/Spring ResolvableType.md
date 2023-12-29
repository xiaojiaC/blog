---
title: Spring ResolvableType
date: 2023-11-12 20:22:23
categories:
  - [JAVA, Spring]
tags:
  - spring
  - spring core
---

## Spring ResolvableType

### 类型概念

在 JDK1.5 之前所有的原始类型都通过字节码文件类`Class`进行抽象。`Class`类的一个具体对象就代表一个指定的原始类型。从 JDK1.5 加入了泛型类，扩充了数据类型，在 **原始类型** 基础上扩充了 **类型变量**、**通配符类型**、**参数化类型**、**泛型数组类型**。`Type`是 Java 语言中所有类型（`Class`）的公共父接口。

{% asset_img Type.png %}

- 类型变量（`TypeVariable`）：是各种类型变量的公共父接口，就是泛型里面的类似`T`、`E`。 例如：`List<T>`中的`T`类型。
- 通配符类型（`WildcardType`）：又叫泛型表达式类型。例如：`List<?>`中的`?`，`List<? extends Number>`中的`? extends Number`或`Set<? super Integer>`中的`? super Integer`。
- 参数化类型（`ParameterizedType`）：泛型类型。例如：`List<E>`、`Map<K, V>`、`List<? extends Number>`带有类型参数的类型。
  - 注意：`TypeVariable`代表着泛型中的变量，而`ParameterizedType`则代表整个泛型。
- 泛型数组类型（`GenericArrayType`）：并不是我们平常所使用的数组`String[]` 、`byte[]`。而是带有泛型的数组，例如：`T[]`。
- 原始类型（`Class`）：不仅包括我们平常所指的类、枚举、数组、注解，还包括 8 种基本类型（`byte`、`short`、`int`、`long`、`float`、`double`、`char`和`boolean`）。

<!-- more -->

#### `TypeVariable`

表示类型变量，它是各种类型变量的公共父接口。

- `Type[] getBounds()`：获取此类型变量的上边界类型数组，若无显示定义`extends`，默认为`Object`（类型变量的上边界可能不止一个，因为可以用`&`符号限定多个。这其中有且只能有一个为类或抽象类，且必须放在`extends`后的第一个位置，也就是说若有多个上边界，则第一个`&`之后的必为接口）。例如：`Map<K extends Number, V>`类型中的`K`类型的上边界是`Number`，`V`类型的上边界是`Object`。
- `D getGenericDeclaration()`：获取声明此类型变量的类类型。
- `String getName()`：获取此类型变量的名称。例如: `Map<K,V>`类型中的`K`、`V`之类的名称。
- `AnnotatedType[] getAnnotatedBounds()`：获取此注解类型变量的上边界注解类型数组。

```java
public class TypeVariableTest<K extends Number, V, A extends Deprecated> {

    /**
     * Output：
     *
     * K
     * [class java.lang.Number]
     * [sun.reflect.annotation.AnnotatedTypeFactory$AnnotatedTypeBaseImpl@254989ff]
     * class java.lang.Number
     * class com.xxx.java.type.TypeVariableTest
     *
     * V
     * [class java.lang.Object]
     * [sun.reflect.annotation.AnnotatedTypeFactory$AnnotatedTypeBaseImpl@5d099f62]
     * class java.lang.Object
     * class com.xxx.java.type.TypeVariableTest
     *
     * A
     * [interface java.lang.Deprecated]
     * [sun.reflect.annotation.AnnotatedTypeFactory$AnnotatedTypeBaseImpl@37f8bb67]
     * interface java.lang.Deprecated
     * class com.xxx.java.type.TypeVariableTest
     */
    public static void main(String[] args) {
        TypeVariable<Class<TypeVariableTest>>[] typeParameters = TypeVariableTest.class.getTypeParameters();
        for (TypeVariable<Class<TypeVariableTest>> typeVar : typeParameters) {
            System.out.println(typeVar.getName());
            System.out.println(Arrays.toString(typeVar.getBounds()));
            System.out.println(Arrays.toString(typeVar.getAnnotatedBounds()));
            for (AnnotatedType annotatedBound : typeVar.getAnnotatedBounds()) {
                System.out.println(Arrays.toString(annotatedBound.getAnnotations()));
            }
            System.out.println(typeVar.getGenericDeclaration());
        }
    }
}
```

#### `WildcardType`

表示一个通配符类型表达式，如：`?`、`? extends Number` 或 `? super Integer`。

- `Type[] getUpperBounds()`：获取泛型通配符的上边界类型数组。例如：`? extends Number`上边界为`Number`类型。
- `Type[] getLowerBounds()`：获取泛型通配符的下边界类型数组。例如：`? super Integer`下边界为`Integer`类型。

```java
public class WildcardTypeTest {

    Map<? extends Number, ? super Integer> users;

    public static void main(String[] args) throws Exception {
        Field field = WildcardTypeTest.class.getDeclaredField("users");
        ParameterizedType parameterizedType = (ParameterizedType) field.getGenericType();
        Type[] actualTypeArguments = parameterizedType.getActualTypeArguments();
        WildcardType wildcardType0 = (WildcardType) actualTypeArguments[0];
        System.out.println(Arrays.toString(wildcardType0.getUpperBounds())); // [class java.lang.Number]
        System.out.println(Arrays.toString(wildcardType0.getLowerBounds())); // []

        WildcardType wildcardType1 = (WildcardType) actualTypeArguments[1];
        System.out.println(Arrays.toString(wildcardType1.getUpperBounds())); // [class java.lang.Object]
        System.out.println(Arrays.toString(wildcardType1.getLowerBounds())); // [class java.lang.Integer]
    }
}
```

#### `ParameterizedType`

表示参数化类型，如：`Collection<String>`。

- `Type[] getActualTypeArguments()`：获取该类型的实际的类型参数数组。例如: `Map<K,V>`类型中的`K`、`V`的类型。
- `Type getRawType()`：获取声明该类型的原始类或接口类型。例如: `Map<K,V>`类型中的`Map`类型。
- `Type getOwnerType()`：获取该类型所属的类型（内部类所属的类型），如果此类型为顶层类型，则返回`null`。例如：`Map.Entry<K,V>`类型其所有者类型是`Map`类型。

```java
public class ParameterizedTypeTest {

    Map<String, Long> userIds;
    Map.Entry<String, Integer> item;

    public static void main(String[] args) throws Exception {
        Field userIdsField = ParameterizedTypeTest.class.getDeclaredField("userIds");
        ParameterizedType type = (ParameterizedType) userIdsField.getGenericType();
        System.out.println(type.getActualTypeArguments()[0] + "," + type.getActualTypeArguments()[1]); // class java.lang.String,class java.lang.Long
        System.out.println(type.getRawType()); // interface java.util.Map
        System.out.println(type.getOwnerType()); // null

        Field itemField = ParameterizedTypeTest.class.getDeclaredField("item");
        type = (ParameterizedType) itemField.getGenericType();
        System.out.println(type.getActualTypeArguments()[0] + "," + type.getActualTypeArguments()[1]); // class java.lang.String,class java.lang.Integer
        System.out.println(type.getRawType()); // interface java.util.Map$Entry
        System.out.println(type.getOwnerType()); // interface java.util.Map
    }
}
```

#### `GenericArrayType`

表示一种数组类型，其元素类型为参数化类型或类型变量。

- `Type getGenericComponentType()`：获取泛型数组中元素的类型。例如：`T[]`数组的元素类型为`T`类型。

```java
public class GenericArrayTypeTest<T> {

    T[][] elements;

    public static void main(String[] args) throws Exception {
        Field field = GenericArrayTypeTest.class.getDeclaredField("elements");
        GenericArrayType twoDimArrayType = (GenericArrayType) field.getGenericType();
        GenericArrayType oneDimArrayType = (GenericArrayType) twoDimArrayType.getGenericComponentType();
        System.out.println(oneDimArrayType); // T[]
        System.out.println(oneDimArrayType.getGenericComponentType()); // T
    }
}
```

#### `Class`

- `Type[] getGenericInterfaces()`：返回类实例的接口的泛型类型数组。
- `Type getGenericSuperclass()`：返回类实例的直接父类的泛型类型。

```java
    public static void main(String[] args) throws Exception {
        System.out.println(HashMap.class.getGenericSuperclass()); // java.util.AbstractMap<K, V>
        System.out.println(Arrays.toString(HashMap.class.getGenericInterfaces())); // [java.util.Map<K, V>, interface java.lang.Cloneable, interface java.io.Serializable]
    }
```

#### `Type`的作用

泛型擦除的原因以及 Java 中`Type`的作用？

其实在 JDK1.5 之前 Java 中只有原始类型而没有泛型类型，而在 JDK1.5 之后引入泛型，但是这种泛型仅仅存在于编译阶段，**当在 JVM 运行的过程中，与泛型相关的信息将会被擦除**，如`List<Integer>`与`List<? extends Number>`都将会在运行时被擦除成为`List`这个类型。而类型擦除机制存在的原因正是因为如果在运行时存在泛型，那么将要修改 JVM 指令集，这是非常致命的。

此外，原始类型会生成字节码文件对象，而泛型类型相关的类型并不会生成与其相对应的字节码文件（因为泛型类型将会被擦除），因此无法将泛型相关的新类型与`Class`相统一。因此，为了程序的扩展性以及为了开发需要去反射操作这些类型，就引入了`Type`这个类型，并且新增了`ParameterizedType`、`TypeVariable`、`GenericArrayType`、`WildcardType`四个表示泛型相关的类型，再加上原始类型`Class`，这样就可以用`Type`类型的参数来统一表示接收以上五种子类的实参或者返回值类型就是`Type`类型的参数。统一了与泛型有关的类型和原始类型`Class`，而且这样一来，我们也可以通过反射获取泛型类型参数。

### `ResolvableType`

为了简化对泛型信息的获取，Spring4 开始提供了一个`ResolvableType`，允许你将类、接口和参数类型解析为一种可操作的形式，以便在运行时动态地创建对象、获取类型信息以及进行其他相关的操作。

#### 如何创建

使用 ResolvableType，需要先获取其实例，泛型类型可以存在于类、成员变量、构造器参数、成员方法参数、方法返回值，对应于这些泛型类型可以存在的位置，ResolvableType 提供了一些将这些泛型类型信息转换为 ResolvableType 的静态方法，常见的方法如下：

```java
public class ResolvableType implements Serializable {

    // 根据原始类型Class创建。使用完整的泛型类型信息进行可分配性检查，例如：ResolvableType.forClass(MyArrayList.class)。
    public static ResolvableType forClass(@Nullable Class<?> clazz);

    // 根据原始类型信息创建。仅对原始类进行可分配性检查（类似于Class.isAssignableFrom）它用作包装器，例如：ResolvableType.forRawClass(List.class)
    public static ResolvableType forRawClass(@Nullable Class<?> clazz);

    // 根据某一种类型创建。
    public static ResolvableType forType(@Nullable Type type);

    // 根据成员变量创建
    public static ResolvableType forField(Field field);

    // 根据构造器参数创建
    public static ResolvableType forConstructorParameter(Constructor<?> constructor, int parameterIndex);

    // 根据实例创建。该实例不传递泛型信息，但如果它实现了ResolvableTypeProvider，则可以使用更精确的ResolvableType
    public static ResolvableType forInstance(Object instance);

    // 根据方法参数创建
    public static ResolvableType forMethodParameter(Method method, int parameterIndex);

    // 根据方法的返回值创建
    public static ResolvableType forMethodReturnType(Method method);

}
```

#### 如何使用

ResolvableType 定义了一些方法可以用于获取泛型信息，具体如下：

```java
public class ResolvableType implements Serializable {

    // 获取泛型数组的元素类型
    public ResolvableType getComponentType();

    // 获取类型继承的直接父类型
    public ResolvableType getSuperType();

    // 获取类型实现的直接接口类型
    public ResolvableType[] getInterfaces();

    // 获取底层Java Class原始类型
    public Class<?> getRawClass();

    // 获取底层Java Type类型
    public Type getType();

    // 获取泛型的实际类型，索引位置从0开始
    // 例如：给定类型 Map<String, List<Integer>>，getGeneric(0)将得到String；getGeneric(1, 0)将得到Integer
    public ResolvableType getGeneric(@Nullable int... indexes);
    public ResolvableType[] getGenerics();

    // 获取指定嵌套级别的类型，嵌套级别从1开始。
    // 嵌套级别是指应该返回的具体泛型参数。嵌套级别为1表示此类型；为2表示第一个嵌套泛型；为3表示第二个；以此类推
    // 例如：给定类型 List<Set<Integer>>，级别1指的是 List，级别2指的是 Set，级别3指的是 Integer。
    public ResolvableType getNested(int nestingLevel);
    // typeIndexesPerLevel Map可用于引用给定级别的特定泛型。
    // 例如：给定Map<K,V> 索引0表示K；而1表示V；如果参数Map不包含特定级别的值，则将使用最后一个泛型类型（例如V）。
    // 例如：给定类型 Map<String, List<Integer>>， getNested(2, {2, 0})将得到String；getNested(2, {2, 1})将得到List<Integer>；getNested(3, {3, 0})将得到Integer
    public ResolvableType getNested(int nestingLevel, @Nullable Map<Integer, Integer> typeIndexesPerLevel);

    // 当前实例是否包含泛型参数
    public boolean hasGenerics();

    // 当前实例是否为数组
    public boolean isArray();

    // 当前实例是否为给定参数的类型或父类型
    public boolean isAssignableFrom(Class<?> other);
    public boolean isAssignableFrom(ResolvableType other);

    // 将此类型解析为Class，如果无法解析该类型，则返回null。如果直接解析失败，此方法将考虑 TypeVariables 和 WildcardTypes 的边界；但是Object.class 的边界将被忽略。
    public Class<?> resolve();
    // 将特定泛型参数解析为Class
    public Class<?> resolveGeneric(int... indexes)
}
```

#### 实现分析

基于以下示例，对`ResolvableType`解析构造过程进行分析，了解其实现后即类通其中大多数方法的实现。

```java
public class ResolvableTypeTest {

    private Map<String, List<Integer>> map;

    public static void main(String[] args) {
        Field field = ReflectionUtils.findField(ResolvableTypeTest.class, "map");
        ResolvableType type = ResolvableType.forField(field);

        // 获取嵌套级别1的类型，使用默认索引
        ResolvableType nestedType1 = type.getNested(1);
        System.out.println(nestedType1); // java.util.Map<java.lang.String, java.util.List<java.lang.Integer>>


        // 获取嵌套级别2的类型，使用自定义索引，且指定获取级别2的第一个泛型
        Map<Integer, Integer> typeIndexes = new HashMap<>();
        typeIndexes.put(2, 0);
        ResolvableType nestedType2 = type.getNested(2, typeIndexes);
        System.out.println(nestedType2); // java.lang.String
    }
}
```

执行完`ResolvableType.forField(field)`后，会构造出该字段对应的包装类型`ResolvableType`，其内核心成员变量已被赋值为：

{% asset_img ResolvableType.png %}

```java org.springframework.core.ResolvableType
public class ResolvableType implements Serializable {

    ......

    private static final ConcurrentReferenceHashMap<ResolvableType, ResolvableType> cache =
                new ConcurrentReferenceHashMap<>(256);

    private ResolvableType(Type type, @Nullable TypeProvider typeProvider, @Nullable VariableResolver variableResolver) {
        this.type = type;
        this.typeProvider = typeProvider;
        this.variableResolver = variableResolver;
        this.componentType = null;
        this.hash = calculateHashCode();  // 按以上属性计算hash
        this.resolved = null;
    }

    private ResolvableType(Type type, @Nullable TypeProvider typeProvider,
            @Nullable VariableResolver variableResolver, @Nullable Integer hash) {
        this.type = type;
        this.typeProvider = typeProvider;
        this.variableResolver = variableResolver;
        this.componentType = null;
        this.hash = hash;
        this.resolved = resolveClass(); // 开始解决Class
    }

    private Class<?> resolveClass() {
        if (this.type == EmptyType.INSTANCE) { // hacked的空类型直接返回null
            return null;
        }
        if (this.type instanceof Class) { // Class类型直接返回
            return (Class<?>) this.type;
        }
        if (this.type instanceof GenericArrayType) { // 泛型数组类型则解析数组元素类型后返回 元素数组类型
            Class<?> resolvedComponent = getComponentType().resolve();
            return (resolvedComponent != null ? Array.newInstance(resolvedComponent, 0).getClass() : null);
        }
        return resolveType().resolve(); // 其他则解决类型后返回
    }

    ResolvableType resolveType() {
        if (this.type instanceof ParameterizedType) { // 参数化类型，获取声明该类型的原始类或接口类型的ResolvableType
            return forType(((ParameterizedType) this.type).getRawType(), this.variableResolver);
        }
        if (this.type instanceof WildcardType) { // 通配符类型
            Type resolved = resolveBounds(((WildcardType) this.type).getUpperBounds()); // 先获取上边界类型数组第一个元素类型
            if (resolved == null) {
                resolved = resolveBounds(((WildcardType) this.type).getLowerBounds()); // 再获取下边界类型数组第一个元素类型
            }
            return forType(resolved, this.variableResolver); // 获取边界类型的ResolvableType
        }
        if (this.type instanceof TypeVariable) { // 类型变量类型
            TypeVariable<?> variable = (TypeVariable<?>) this.type;
            // Try default variable resolution
            if (this.variableResolver != null) {
                ResolvableType resolved = this.variableResolver.resolveVariable(variable);
                if (resolved != null) {
                    return resolved;
                }
            }
            // Fallback to bounds
            return forType(resolveBounds(variable.getBounds()), this.variableResolver); // 获取此类型变量的上边界类型数组第一个元素类型的ResolvableType
        }
        return NONE; // 空类型
    }

    public static ResolvableType forField(Field field) {
        Assert.notNull(field, "Field must not be null");
        return forType(null, new FieldTypeProvider(field), null);
    }

    static ResolvableType forType(@Nullable Type type, @Nullable TypeProvider typeProvider, @Nullable VariableResolver variableResolver) {
        // 未直接指定类型，根据 TypeProvider 获取类型
        if (type == null && typeProvider != null) {
            type = SerializableTypeWrapper.forTypeProvider(typeProvider);
        }
        if (type == null) {
            return NONE;
        }

        // 对于简单的类引用直接构建，不需要昂贵的解析，也不值得缓存......
        if (type instanceof Class) {
            return new ResolvableType(type, typeProvider, variableResolver, (ResolvableType) null);
        }

        // 由于没有专门清理线程，因此访问时清除空条目
        cache.purgeUnreferencedEntries();

        // 其他类型实例化后进行缓存
        ResolvableType resultType = new ResolvableType(type, typeProvider, variableResolver); // 初次实例化会计算实例hash（缓存键）
        ResolvableType cachedType = cache.get(resultType);
        if (cachedType == null) {
            cachedType = new ResolvableType(type, typeProvider, variableResolver, resultType.hash); // 再次实例化会尝试解决Class（缓存值）
            cache.put(cachedType, cachedType);
        }
        resultType.resolved = cachedType.resolved; // 已解决的类型(resolved)复制
        return resultType;
    }

    ......
}
```

```java org.springframework.core.SerializableTypeWrapper
final class SerializableTypeWrapper { // 见名知意

    private static final Class<?>[] SUPPORTED_SERIALIZABLE_TYPES = {
            GenericArrayType.class, ParameterizedType.class, TypeVariable.class, WildcardType.class};

    ......

    static Type forTypeProvider(TypeProvider provider) {
        Type providedType = provider.getType();
        if (providedType == null || providedType instanceof Serializable) {
            // 不需要可串行化的类型包装(例如 java.lang.Class)
            return providedType;
        }
        if (GraalDetector.inImageCode() || !Serializable.class.isAssignableFrom(Class.class)) {
            // Let's skip any wrapping attempts if types are generally not serializable in
            // the current runtime environment (even java.lang.Class itself, e.g. on Graal)
            return providedType;
        }

        // 获取给定TypeProvider的可串行化类型代理...
        Type cached = cache.get(providedType);
        if (cached != null) {
            return cached;
        }
        for (Class<?> type : SUPPORTED_SERIALIZABLE_TYPES) {
            if (type.isInstance(providedType)) {
                ClassLoader classLoader = provider.getClass().getClassLoader();
                Class<?>[] interfaces = new Class<?>[] {type, SerializableTypeProxy.class, Serializable.class};
                // 生成类型代理，实现以上3个接口，对支持的序列化类型任何返回Type或Type[]的方法进行代理，统一返回ResolvableType
                InvocationHandler handler = new TypeProxyInvocationHandler(provider);
                cached = (Type) Proxy.newProxyInstance(classLoader, interfaces, handler);
                cache.put(providedType, cached);
                return cached;
            }
        }
        throw new IllegalArgumentException("Unsupported Type class: " + providedType.getClass().getName());
    }

    interface SerializableTypeProxy {

        /**
        * 返回类型提供程序
        */
        TypeProvider getTypeProvider();
    }

    interface TypeProvider extends Serializable {

        /**
         * 返回（未被代理Serializable）的原始Type
         */
        @Nullable
        Type getType();

        /**
         * 返回类型的源，如果未知则返回 null
         */
        @Nullable
        default Object getSource() {
            return null;
        }
    }

    // 提供序列化支持并增强任何返回Type或Type[]的方法。
    private static class TypeProxyInvocationHandler implements InvocationHandler, Serializable {

        private final TypeProvider provider;

        public TypeProxyInvocationHandler(TypeProvider provider) {
            this.provider = provider;
        }

        @Override
        @Nullable
        public Object invoke(Object proxy, Method method, @Nullable Object[] args) throws Throwable {
            if (method.getName().equals("equals") && args != null) {
                Object other = args[0];
                // 其实就是看是否也是个代理，是的话先解包装后（((SerializableTypeProxy) type).getTypeProvider().getType()）再比较
                if (other instanceof Type) {
                    other = unwrap((Type) other);
                }
                return ObjectUtils.nullSafeEquals(this.provider.getType(), other);
            }
            else if (method.getName().equals("hashCode")) {
                return ObjectUtils.nullSafeHashCode(this.provider.getType());
            }
            else if (method.getName().equals("getTypeProvider")) {
                return this.provider;
            }

            if (Type.class == method.getReturnType() && args == null) { // 无参方法，返回值为Type.class
                return forTypeProvider(new MethodInvokeTypeProvider(this.provider, method, -1)); // 代理返回MethodInvokeTypeProvider类型
            }
            else if (Type[].class == method.getReturnType() && args == null) { // 无参方法，返回值为Type[].class
                Type[] result = new Type[((Type[]) method.invoke(this.provider.getType())).length];
                for (int i = 0; i < result.length; i++) {
                    result[i] = forTypeProvider(new MethodInvokeTypeProvider(this.provider, method, i));
                }
                return result;
            }

            try {
                return method.invoke(this.provider.getType(), args); // 其他非代理方法则委托原类型执行
            }
            catch (InvocationTargetException ex) {
                throw ex.getTargetException();
            }
        }
    }

     static class FieldTypeProvider implements TypeProvider {

        private final String fieldName;

        private final Class<?> declaringClass;

        private transient Field field;

        public FieldTypeProvider(Field field) {
            this.fieldName = field.getName();
            this.declaringClass = field.getDeclaringClass();
            this.field = field;
        }

        @Override
        public Type getType() {
            return this.field.getGenericType(); // 其实就是获取该字段的底层java Type
        }

        @Override
        public Object getSource() {
            return this.field; // 类型所属源，其实就是该字段
        }

        // 支持从输入流中读取并反序列化该对象及field字段
        private void readObject(ObjectInputStream inputStream) throws IOException, ClassNotFoundException {
            inputStream.defaultReadObject();
            try {
                this.field = this.declaringClass.getDeclaredField(this.fieldName);
            }
            catch (Throwable ex) {
                throw new IllegalStateException("Could not find original class structure", ex);
            }
        }
    }

    static class MethodInvokeTypeProvider implements TypeProvider {

        private final TypeProvider provider;

        private final String methodName;

        private final Class<?> declaringClass;

        private final int index;

        private transient Method method;

        @Nullable
        private transient volatile Object result;

        public MethodInvokeTypeProvider(TypeProvider provider, Method method, int index) {
            this.provider = provider;
            this.methodName = method.getName();
            this.declaringClass = method.getDeclaringClass();
            this.index = index;
            this.method = method;
        }

        // 比如：`ParameterizedType`的`Type getRawType()`方法，这里代理后返回的其实是`MethodInvokeTypeProvider`，该类型提供者`getType()`方法返回的才是之前的结果。
        @Override
        @Nullable
        public Type getType() {
            Object result = this.result;
            if (result == null) {
                // 对所提供类型的目标方法的惰性调用
                result = ReflectionUtils.invokeMethod(this.method, this.provider.getType());
                // 缓存结果以便进一步调用getType()
                this.result = result;
            }
            return (result instanceof Type[] ? ((Type[]) result)[this.index] : (Type) result);
        }

        @Override
        @Nullable
        public Object getSource() {
            return null;
        }

        // 支持从输入流中读取并反序列化该对象及method字段
        private void readObject(ObjectInputStream inputStream) throws IOException, ClassNotFoundException {
            inputStream.defaultReadObject();
            Method method = ReflectionUtils.findMethod(this.declaringClass, this.methodName);
            if (method == null) {
                throw new IllegalStateException("Cannot find method on deserialization: " + this.methodName);
            }
            if (method.getReturnType() != Type.class && method.getReturnType() != Type[].class) {
                throw new IllegalStateException(
                        "Invalid return type on deserialized method - needs to be Type or Type[]: " + method);
            }
            this.method = method;
        }
    }
}
```

在上述构造流程结束后，该`ResolvableType`对象的`resolved`字段会被解决并赋值为`java.util.Map`，`generics`成员并未赋值。但我们 debug 看却发现，`generics`成员也被解析并赋值完毕。

其实是由于 idea IDEA debug 时，当 debug 到某个对象时，会调用对象的`toString()`方法，用来在 debug 界面显示对象信息。

可以打开`File | Settings | Build, Execution, Deployment | Debugger | Data Views | Java` 设置关闭`Enable 'toString' object view`选项。

那为什么打开这个选项，`generics`成员也被赋值完毕了呢？让我们定位到`ResolvableType#toString()`方法源码一探究竟。

```java org.springframework.core.ResolvableType
    public String toString() {
        if (isArray()) {
            return getComponentType() + "[]";
        }
        if (this.resolved == null) {
            return "?";
        }
        if (this.type instanceof TypeVariable) {
            TypeVariable<?> variable = (TypeVariable<?>) this.type;
            if (this.variableResolver == null || this.variableResolver.resolveVariable(variable) == null) {
                // Don't bother with variable boundaries for toString()...
                // Can cause infinite recursions in case of self-references
                return "?";
            }
        }
        // 可以看到这里其实会诱发解析类型中的泛型
        if (hasGenerics()) {
            return this.resolved.getName() + '<' + StringUtils.arrayToDelimitedString(getGenerics(), ", ") + '>';
        }
        return this.resolved.getName();
    }

    public boolean hasGenerics() {
        return (getGenerics().length > 0);
    }

    public ResolvableType[] getGenerics() {
        if (this == NONE) {
            return EMPTY_TYPES_ARRAY;
        }
        ResolvableType[] generics = this.generics;
        if (generics == null) {
            if (this.type instanceof Class) {
                Type[] typeParams = ((Class<?>) this.type).getTypeParameters();
                generics = new ResolvableType[typeParams.length];
                for (int i = 0; i < generics.length; i++) {
                    generics[i] = ResolvableType.forType(typeParams[i], this);
                }
            }
            // 而这里进入该case，再次诱发执行字段类型代理对象的已代理方法 getActualTypeArguments
            else if (this.type instanceof ParameterizedType) {
                Type[] actualTypeArguments = ((ParameterizedType) this.type).getActualTypeArguments();
                generics = new ResolvableType[actualTypeArguments.length];
                for (int i = 0; i < actualTypeArguments.length; i++) {
                    generics[i] = forType(actualTypeArguments[i], this.variableResolver);
                }
            }
            else {
                generics = resolveType().getGenerics();
            }
            this.generics = generics;
        }
        return generics;
    }
```

下面用一张图总结示例`ResolvableType`的解析构造过程：

{% asset_img ResolvableTypeTest.png %}
