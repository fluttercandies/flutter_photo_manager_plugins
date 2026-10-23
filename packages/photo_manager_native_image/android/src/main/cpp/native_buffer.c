// Buffers handed to Dart must come from the same libc heap that
// `package:ffi`'s `malloc.free` releases, so they are allocated here rather
// than with `ByteBuffer.allocateDirect`.
#include <jni.h>
#include <stdint.h>
#include <stdlib.h>

JNIEXPORT jlong JNICALL
Java_com_fluttercandies_photo_1manager_1native_1image_NativeBuffer_allocate(
    JNIEnv *env, jclass clazz, jlong size) {
  (void)env;
  (void)clazz;
  if (size <= 0) {
    return 0;
  }
  return (jlong)(intptr_t)malloc((size_t)size);
}

JNIEXPORT jobject JNICALL
Java_com_fluttercandies_photo_1manager_1native_1image_NativeBuffer_wrap(
    JNIEnv *env, jclass clazz, jlong pointer, jlong size) {
  (void)clazz;
  return (*env)->NewDirectByteBuffer(env, (void *)(intptr_t)pointer, size);
}

JNIEXPORT void JNICALL
Java_com_fluttercandies_photo_1manager_1native_1image_NativeBuffer_free(
    JNIEnv *env, jclass clazz, jlong pointer) {
  (void)env;
  (void)clazz;
  free((void *)(intptr_t)pointer);
}
