---
title: "photo_manager 中 java version 的配置方式"
weight: 1
---

photo_manager 为了保证旧版本 AGP/flutter SDK 的兼容性
所以支持通过配置文件/环境变量等方式来配置项目的 java 版本

它们会按照如下的顺序来查找 java 版本:

1. 通过 `gradle.properties` 中的 `java.version` 配置，它的值应该是一个 java 版本号的字符格式
   例如: `1.8` `11` `17` `21` 等
2. 通过 `JAVA_HOME` 环境变量，它应该是一个 jdk 的安装路径，java 一般位于 `$JAVA_HOME/bin/java`
3. 通过 `gradle.properties` 中的 `java.home` 来配置
4. 通过读取 JDK 的运行时属性 `java.home` 来读取
5. 如果以上都没有找到，那么会使用 JavaVersion.current()

以上的4、5步骤应该使用的是 Gradle 配置中的 JDK，通常是相同的
