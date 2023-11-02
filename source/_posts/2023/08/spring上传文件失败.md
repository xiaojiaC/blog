---
title: Spring MVC文件上传为何突然失败？
date: 2023-08-26 22:00:32
categories:
  - [JAVA, Spring]
tags:
  - java
  - spring
  - spring mvc
---

## 问题现象

生产素材上传正常运行已有一段时间，突然某天运营告知素材文件无法上传，奇怪的是最近一直无此块代码相关变更，于是乎就这样走进“幽灵探索”之路...

```
DEBUG 29208 -- [http-nio-8080-exec-4] DispatcherServlet : POST "/cmsapi/material/upload", parameters={masked}
DEBUG 29208 -- [http-nio-8080-exec-4] PropertySourcedRequestMappingHandlerMapping : looking up handler for path: /cmsapi/material/upload
DEBUG 29208 -- [http-nio-8080-exec-4] RequestMappingHandlerMapping : Mapped to com.xxx.cms.controller.MaterialController#uploadMaterials(UploadMaterialsRequest)
DEBUG 29208 -- [http-nio-8080-exec-4] ServletInvocableHandlerMethod : Could not resolve parameter [0] in public com.xxx.cms.vo.Response<com.xxx.cms.vo.ObjectResult<com.xxx.cms.service.common.oss.OssFileDto>> com.xxx.cms.controller.MaterialController.uploadMaterials(com.xxx.cms.request.UploadMaterialsRequest): org.springframework.validation.BeanPropertyBindingResult: 1 errors
Field error in object 'uploadMaterialsRequest' on field 'file': rejected value [null]; codes [NotNull.uploadMaterialsRequest.file,NotNull.file,NotNull.org.springframework.web.multipart.MultipartFile,NotNull]; arguments [org.springframework.context.support.DefaultMessageSourceResolvable: codes [uploadMaterialsRequest.file,file]; arguments []; default message [file]]; default message [material.file.null]
DEBUG 29208 -- [http-nio-8080-exec-4] ExceptionHandlerExceptionResolver : Using @ExceptionHandler com.xxx.cms.advice.ApiExceptionAdvice#handleBindException(BindException)
INFO 29208 -- [http-nio-8080-exec-4] ApiExceptionAdvice : org.springframework.validation.BeanPropertyBindingResult: 1 errors
Field error in object 'uploadMaterialsRequest' on field 'file': rejected value [null]; codes [NotNull.uploadMaterialsRequest.file,NotNull.file,NotNull.org.springframework.web.multipart.MultipartFile,NotNull]; arguments [org.springframework.context.support.DefaultMessageSourceResolvable: codes [uploadMaterialsRequest.file,file]; arguments []; default message [file]]; default message [material.file.null]
org.springframework.validation.BindException: org.springframework.validation.BeanPropertyBindingResult: 1 errors
Field error in object 'uploadMaterialsRequest' on field 'file': rejected value [null]; codes [NotNull.uploadMaterialsRequest.file,NotNull.file,NotNull.org.springframework.web.multipart.MultipartFile,NotNull]; arguments [org.springframework.context.support.DefaultMessageSourceResolvable: codes [uploadMaterialsRequest.file,file]; arguments []; default message [file]]; default message [material.file.null]
at org.springframework.web.method.annotation.ModelAttributeMethodProcessor.resolveArgument(ModelAttributeMethodProcessor.java:164) ~[spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.method.support.HandlerMethodArgumentResolverComposite.resolveArgument(HandlerMethodArgumentResolverComposite.java:121) ~[spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.method.support.InvocableHandlerMethod.getMethodArgumentValues(InvocableHandlerMethod.java:167) ~[spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.method.support.InvocableHandlerMethod.invokeForRequest(InvocableHandlerMethod.java:134) ~[spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.mvc.method.annotation.ServletInvocableHandlerMethod.invokeAndHandle(ServletInvocableHandlerMethod.java:106) ~[spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerAdapter.invokeHandlerMethod(RequestMappingHandlerAdapter.java:888) ~[spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerAdapter.handleInternal(RequestMappingHandlerAdapter.java:793) ~[spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.mvc.method.AbstractHandlerMethodAdapter.handle(AbstractHandlerMethodAdapter.java:87) ~[spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.DispatcherServlet.doDispatch(DispatcherServlet.java:1040) [spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.DispatcherServlet.doService(DispatcherServlet.java:943) [spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.FrameworkServlet.processRequest(FrameworkServlet.java:1006) [spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.servlet.FrameworkServlet.doPost(FrameworkServlet.java:909) [spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at javax.servlet.http.HttpServlet.service(HttpServlet.java:660) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.springframework.web.servlet.FrameworkServlet.service(FrameworkServlet.java:883) [spring-webmvc-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at javax.servlet.http.HttpServlet.service(HttpServlet.java:741) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter(ApplicationFilterChain.java:231) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.ApplicationFilterChain.doFilter(ApplicationFilterChain.java:166) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.springframework.web.filter.RequestContextFilter.doFilterInternal(RequestContextFilter.java:100) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.filter.OncePerRequestFilter.doFilter(OncePerRequestFilter.java:119) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter(ApplicationFilterChain.java:193) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.ApplicationFilterChain.doFilter(ApplicationFilterChain.java:166) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.springframework.web.filter.FormContentFilter.doFilterInternal(FormContentFilter.java:93) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.filter.OncePerRequestFilter.doFilter(OncePerRequestFilter.java:119) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter(ApplicationFilterChain.java:193) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.ApplicationFilterChain.doFilter(ApplicationFilterChain.java:166) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.springframework.web.filter.CharacterEncodingFilter.doFilterInternal(CharacterEncodingFilter.java:201) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.filter.OncePerRequestFilter.doFilter(OncePerRequestFilter.java:119) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter(ApplicationFilterChain.java:193) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.ApplicationFilterChain.doFilter(ApplicationFilterChain.java:166) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.springframework.web.filter.CorsFilter.doFilterInternal(CorsFilter.java:92) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.springframework.web.filter.OncePerRequestFilter.doFilter(OncePerRequestFilter.java:119) [spring-web-5.2.3.RELEASE.jar:5.2.3.RELEASE]
at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter(ApplicationFilterChain.java:193) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.ApplicationFilterChain.doFilter(ApplicationFilterChain.java:166) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.StandardWrapperValve.invoke(StandardWrapperValve.java:202) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.StandardContextValve.invoke(StandardContextValve.java:96) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.authenticator.AuthenticatorBase.invoke(AuthenticatorBase.java:541) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.StandardHostValve.invoke(StandardHostValve.java:139) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.valves.ErrorReportValve.invoke(ErrorReportValve.java:92) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.core.StandardEngineValve.invoke(StandardEngineValve.java:74) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.catalina.connector.CoyoteAdapter.service(CoyoteAdapter.java:343) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.coyote.http11.Http11Processor.service(Http11Processor.java:367) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.coyote.AbstractProcessorLight.process(AbstractProcessorLight.java:65) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.coyote.AbstractProtocol$ConnectionHandler.process(AbstractProtocol.java:860) [tomcat-embed-core-9.0.30.jar:9.0.30]
	at org.apache.tomcat.util.net.NioEndpoint$SocketProcessor.doRun(NioEndpoint.java:1598) [tomcat-embed-core-9.0.30.jar:9.0.30]
at org.apache.tomcat.util.net.SocketProcessorBase.run(SocketProcessorBase.java:49) [tomcat-embed-core-9.0.30.jar:9.0.30]
at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1142) [?:1.8.0_65]
at java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:617) [?:1.8.0_65]
	at org.apache.tomcat.util.threads.TaskThread$WrappingRunnable.run(TaskThread.java:61) [tomcat-embed-core-9.0.30.jar:9.0.30]
at java.lang.Thread.run(Thread.java:745) [?:1.8.0_65]
DEBUG 29208 -- [http-nio-8080-exec-4] RequestResponseBodyMethodProcessor : Using 'application/json', given [application/json] and supported [application/json, application/*+json, application/json, application/*+json, application/cbor]
DEBUG 29208 -- [http-nio-8080-exec-4] RequestResponseBodyMethodProcessor : Writing [Response(code=400, msg=无效请求, data=null, errors=[com.xxx.cms.vo.FieldDefaultVo@7c382733])]
DEBUG 29208 -- [http-nio-8080-exec-4] ExceptionHandlerExceptionResolver : Resolved [org.springframework.validation.BindException: org.springframework.validation.BeanPropertyBindingResult: 1 errors
Field error in object 'uploadMaterialsRequest' on field 'file': rejected value [null]; codes [NotNull.uploadMaterialsRequest.file,NotNull.file,NotNull.org.springframework.web.multipart.MultipartFile,NotNull]; arguments [org.springframework.context.support.DefaultMessageSourceResolvable: codes [uploadMaterialsRequest.file,file]; arguments []; default message [file]]; default message [material.file.null]]
DEBUG 29208 -- [http-nio-8080-exec-4] DispatcherServlet : Completed 200 OK
```

<!-- more -->

### 运行环境

```
java: 8
spring-boot-starter-web: 2.2.4.RELEASE
spring-boot-starter-log4j2: 2.2.4.RELEASE
```

### 我的代码

```java
@PostMapping(value = "material/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
public Response<ObjectResult<OssFileDto>> upload(@Valid UploadMaterialsRequest request) {
    OssFileDto ossFile = materialService.bulkUpload(request);
    return Response.success(ObjectResult.of(ossFile, f -> {
        fileRepository.setOssFileToken(request.getType(), f.getFileToken());
    }));
}

@Data
public class UploadMaterialsRequest {

    @NotNull(message = "material.type.null")
    @EnumValue(type = MaterialTypeEnum.class, message = "material.type.illegal")
    private Integer type;

    @NotNull(message = "material.file.null")
    private MultipartFile file;
}
```

### 排查之路

首先咨询同事，发现最近上线了一个新特性，但不涉及素材功能相关代码改动，搜索错误日志发现生产{% label primary@竟然 %}开启了`DEBUG`，有相关错误记录，发现 {% label danger@Field error in object 'uploadMaterialsRequest' on field 'file': rejected value [null]; %}目前无法获取到上传的文件，但具体为何突然取不到？
尝试预发环境测试发现功能正常，想看下日志现场于是将日志级别调为`DEBUG`，发现问题复现了。猜测可能是**动态日志级别修改导致**，将线上`DEBUG`关闭后测试发现恢复，那为何日志级别会影响到文件读取呢？

#### 关键调用栈

```java
......
parseRequest:276, FileUploadBase (org.apache.tomcat.util.http.fileupload)
parseParts:2867, Request (org.apache.catalina.connector)  // 解析MultipartFile
parseParameters:3195, Request (org.apache.catalina.connector)
getParameterNames:1159, Request (org.apache.catalina.connector)
getParameterMap:1138, Request (org.apache.catalina.connector)
getParameterMap:443, RequestFacade (org.apache.catalina.connector)
lambda$logRequest$2:964, DispatcherServlet (org.springframework.web.servlet)
apply:-1, 146803671 (org.springframework.web.servlet.DispatcherServlet$$Lambda$867)
traceDebug:86, LogFormatUtils (org.springframework.core.log)
logRequest:956, DispatcherServlet (org.springframework.web.servlet) // 打印请求日志
doService:911, DispatcherServlet (org.springframework.web.servlet)
processRequest:1006, FrameworkServlet (org.springframework.web.servlet)
doPost:909, FrameworkServlet (org.springframework.web.servlet)
service:660, HttpServlet (javax.servlet.http)
```

#### 关键代码段

```java org.apache.catalina.connector.Request
 private void parseParts(boolean explicit) { // explicit为false
    if (parts != null || partsParseException != null) {
        return;
    }
    Context context = getContext();
    MultipartConfigElement mce = getWrapper().getMultipartConfigElement();
    if (mce == null) { // 可以看到这里如果返回null，会跳过后续解析parts
        if(context.getAllowCasualMultipartParsing()) {
            mce = new MultipartConfigElement(null, connector.getMaxPostSize(),
                    connector.getMaxPostSize(), connector.getMaxPostSize());
        } else {
            if (explicit) {
                partsParseException = new IllegalStateException(
                        sm.getString("coyoteRequest.noMultipartConfig"));
                return;
            } else {
                parts = Collections.emptyList();
                return;
            }
        }
    }

    // 解析parts 略...
}
```

观察以上调用栈，可以看到如果开启`DEBUG`模式，spring mvc 会解析请求参数打印请求日志，file 文件流此时已被提前解析读取一次，导致后续参数绑定时再次读取失败。

### 解决方案

1. 关闭`DispatcherServlet`的`DEBUG`模式（但生产有时会利用`ROOT=DEBUG`排查其他问题）
2. 让`StandardWrapper#getMultipartConfigElement()`返回`null`跳过解析（最终采用）

{% asset_img MultipartAutoConfig.PNG SpringBoot Multipart自动配置%}

从上图可以看出默认 springboot 自动配置了 `spring.servlet.multipart.enabled=true`，默认启用`StandardServletMultipartResolver`，会初始化`MultipartConfigElement`；因此我们可以自定义`CommonsMultipartResolver`替换默认的解析器，并关闭`spring.servlet.multipart.enabled`即可实现方案 2。

```xml pom.xml
<dependency>
    <groupId>commons-fileupload</groupId>
    <artifactId>commons-fileupload</artifactId>
    <version>1.5</version>
</dependency>
```

```properties application.properties
spring.servlet.multipart.enabled=false
```

```java WebConfig.java
@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Bean
    public MultipartResolver multipartResolver() {
        CommonsMultipartResolver resolver = new CommonsMultipartResolver();
        resolver.setDefaultEncoding(StandardCharsets.UTF_8.name());
        resolver.setMaxUploadSize(10 * 1024 * 1024); // 10M
        return resolver;
    }
}
```
