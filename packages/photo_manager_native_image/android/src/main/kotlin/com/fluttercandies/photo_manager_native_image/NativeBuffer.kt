package com.fluttercandies.photo_manager_native_image

import java.nio.ByteBuffer

/** `malloc`/`free` on the libc heap, the heap Dart's `malloc.free` releases. */
object NativeBuffer {
    init {
        System.loadLibrary("photo_manager_native_image")
    }

    /** Returns the address, or 0 when allocation failed. */
    @JvmStatic
    external fun allocate(size: Long): Long

    /** Direct [ByteBuffer] view over [pointer]; no copy, no ownership. */
    @JvmStatic
    external fun wrap(pointer: Long, size: Long): ByteBuffer

    @JvmStatic
    external fun free(pointer: Long)
}
