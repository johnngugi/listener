const std = @import("std");
const policy = @import("../artwork.zig");

const CFIndex = isize;
const CFTypeID = usize;
const CFStringEncoding = u32;
const CFNumberType = CFIndex;
const CGImageSourceStatus = i32;

const CFData = opaque {};
const CFDataRef = *const CFData;
const CFMutableDataRef = *CFData;
const CFString = opaque {};
const CFStringRef = *const CFString;
const CFDictionary = opaque {};
const CFDictionaryRef = *const CFDictionary;
const CFNumber = opaque {};
const CFNumberRef = *const CFNumber;
const CFBoolean = opaque {};
const CFBooleanRef = *const CFBoolean;
const CGImageSource = opaque {};
const CGImageSourceRef = *const CGImageSource;
const CGImage = opaque {};
const CGImageRef = *const CGImage;
const CGImageDestination = opaque {};
const CGImageDestinationRef = *const CGImageDestination;

const kCFStringEncodingUTF8: CFStringEncoding = 0x08000100;
const kCFNumberSInt64Type: CFNumberType = 4;
const kCFCompareEqualTo: CFIndex = 0;
const kCGImageStatusComplete: CGImageSourceStatus = 0;

extern var kCFBooleanTrue: CFBooleanRef;
extern var kCGImagePropertyPixelWidth: CFStringRef;
extern var kCGImagePropertyPixelHeight: CFStringRef;
extern var kCGImageSourceCreateThumbnailFromImageAlways: CFStringRef;
extern var kCGImageSourceCreateThumbnailWithTransform: CFStringRef;
extern var kCGImageSourceThumbnailMaxPixelSize: CFStringRef;

extern fn CFRelease(value: *const anyopaque) callconv(.c) void;

extern fn CFGetTypeID(value: *const anyopaque) callconv(.c) CFTypeID;

extern fn CFDataCreate(
    allocator: ?*const anyopaque,
    bytes: [*]const u8,
    length: CFIndex,
) callconv(.c) ?CFDataRef;

extern fn CFDataCreateMutable(
    allocator: ?*const anyopaque,
    capacity: CFIndex,
) callconv(.c) ?CFMutableDataRef;

extern fn CFDataGetLength(data: CFDataRef) callconv(.c) CFIndex;

extern fn CFDataGetBytePtr(data: CFDataRef) callconv(.c) ?[*]const u8;

extern fn CFStringCreateWithCString(
    allocator: ?*const anyopaque,
    c_string: [*:0]const u8,
    encoding: CFStringEncoding,
) callconv(.c) ?CFStringRef;

extern fn CFStringCompare(
    first: CFStringRef,
    second: CFStringRef,
    options: CFIndex,
) callconv(.c) CFIndex;

extern fn CFDictionaryGetValue(
    dictionary: CFDictionaryRef,
    key: *const anyopaque,
) callconv(.c) ?*const anyopaque;

extern fn CFDictionaryCreate(
    allocator: ?*const anyopaque,
    keys: [*]const ?*const anyopaque,
    values: [*]const ?*const anyopaque,
    count: CFIndex,
    key_callbacks: ?*const anyopaque,
    value_callbacks: ?*const anyopaque,
) callconv(.c) ?CFDictionaryRef;

extern fn CFNumberGetTypeID() callconv(.c) CFTypeID;

extern fn CFNumberCreate(
    allocator: ?*const anyopaque,
    number_type: CFNumberType,
    value: *const anyopaque,
) callconv(.c) ?CFNumberRef;

extern fn CFNumberGetValue(
    number: CFNumberRef,
    number_type: CFNumberType,
    value: *anyopaque,
) callconv(.c) bool;

extern fn CGImageSourceCreateWithData(
    data: CFDataRef,
    options: ?CFDictionaryRef,
) callconv(.c) ?CGImageSourceRef;

extern fn CGImageSourceGetCount(source: CGImageSourceRef) callconv(.c) usize;

extern fn CGImageSourceGetStatusAtIndex(
    source: CGImageSourceRef,
    index: usize,
) callconv(.c) CGImageSourceStatus;

extern fn CGImageSourceGetType(source: CGImageSourceRef) callconv(.c) ?CFStringRef;

extern fn CGImageSourceCopyPropertiesAtIndex(
    source: CGImageSourceRef,
    index: usize,
    options: ?CFDictionaryRef,
) callconv(.c) ?CFDictionaryRef;

extern fn CGImageSourceCreateImageAtIndex(
    source: CGImageSourceRef,
    index: usize,
    options: ?CFDictionaryRef,
) callconv(.c) ?CGImageRef;

extern fn CGImageSourceCreateThumbnailAtIndex(
    source: CGImageSourceRef,
    index: usize,
    options: ?CFDictionaryRef,
) callconv(.c) ?CGImageRef;

extern fn CGImageGetWidth(image: CGImageRef) callconv(.c) usize;

extern fn CGImageGetHeight(image: CGImageRef) callconv(.c) usize;

extern fn CGImageRelease(image: CGImageRef) callconv(.c) void;

extern fn CGImageDestinationCreateWithData(
    data: CFMutableDataRef,
    format: CFStringRef,
    image_count: usize,
    options: ?CFDictionaryRef,
) callconv(.c) ?CGImageDestinationRef;

extern fn CGImageDestinationAddImage(
    destination: CGImageDestinationRef,
    image: CGImageRef,
    properties: ?CFDictionaryRef,
) callconv(.c) void;

extern fn CGImageDestinationFinalize(
    destination: CGImageDestinationRef,
) callconv(.c) bool;

/// ImageIO on the project's minimum supported macOS version (12.0) decodes
/// JPEG, PNG, and WebP. Normalized output is JPEG for stable storage support.
pub fn process(
    comptime Artwork: type,
    comptime Format: type,
    allocator: std.mem.Allocator,
    encoded: []const u8,
) std.mem.Allocator.Error!?Artwork {
    const data = CFDataCreate(null, encoded.ptr, @intCast(encoded.len)) orelse return null;
    defer release(data);

    const source = CGImageSourceCreateWithData(data, null) orelse return null;
    defer release(source);
    if (CGImageSourceGetCount(source) == 0) return null;
    if (CGImageSourceGetStatusAtIndex(source, 0) != kCGImageStatusComplete) return null;

    const format = detectFormat(Format, source) orelse return null;
    const dimensions = imageDimensions(source) orelse return null;
    if (!policy.dimensionsAllowed(dimensions.width, dimensions.height)) return null;

    if (encoded.len <= policy.max_encoded_bytes and
        dimensions.width <= policy.max_stored_dimension and
        dimensions.height <= policy.max_stored_dimension)
    {
        const image = CGImageSourceCreateImageAtIndex(source, 0, null) orelse return null;
        defer CGImageRelease(image);
        if (!decodedDimensionsMatch(image, dimensions)) return null;

        return .{
            .format = format,
            .bytes = try allocator.dupe(u8, encoded),
            .width = dimensions.width,
            .height = dimensions.height,
        };
    }

    const image = createNormalizedImage(source, dimensions) orelse return null;
    defer CGImageRelease(image);
    return encodeJpeg(Artwork, Format, allocator, image);
}

const Dimensions = struct {
    width: u32,
    height: u32,
};

fn release(value: anytype) void {
    CFRelease(@ptrCast(value));
}

fn detectFormat(comptime Format: type, source: CGImageSourceRef) ?Format {
    const type_id = CGImageSourceGetType(source) orelse return null;
    if (stringEquals(type_id, "public.jpeg")) return .jpeg;
    if (stringEquals(type_id, "public.png")) return .png;
    if (stringEquals(type_id, "org.webmproject.webp")) return .webp;
    return null;
}

fn stringEquals(value: CFStringRef, expected: [*:0]const u8) bool {
    const expected_string = CFStringCreateWithCString(
        null,
        expected,
        kCFStringEncodingUTF8,
    ) orelse return false;
    defer release(expected_string);
    return CFStringCompare(value, expected_string, 0) == kCFCompareEqualTo;
}

fn imageDimensions(source: CGImageSourceRef) ?Dimensions {
    const properties = CGImageSourceCopyPropertiesAtIndex(source, 0, null) orelse return null;
    defer release(properties);

    const width = dictionaryU32(properties, kCGImagePropertyPixelWidth) orelse return null;
    const height = dictionaryU32(properties, kCGImagePropertyPixelHeight) orelse return null;
    return .{ .width = width, .height = height };
}

fn dictionaryU32(dictionary: CFDictionaryRef, key: CFStringRef) ?u32 {
    const raw = CFDictionaryGetValue(dictionary, @ptrCast(key)) orelse return null;
    if (CFGetTypeID(raw) != CFNumberGetTypeID()) return null;

    const number: CFNumberRef = @ptrCast(raw);
    var value: i64 = 0;
    if (!CFNumberGetValue(number, kCFNumberSInt64Type, &value)) return null;
    if (value <= 0) return null;
    return std.math.cast(u32, value);
}

fn decodedDimensionsMatch(image: CGImageRef, expected: Dimensions) bool {
    return CGImageGetWidth(image) == expected.width and
        CGImageGetHeight(image) == expected.height;
}

fn createNormalizedImage(source: CGImageSourceRef, dimensions: Dimensions) ?CGImageRef {
    if (dimensions.width <= policy.max_stored_dimension and
        dimensions.height <= policy.max_stored_dimension)
    {
        return CGImageSourceCreateImageAtIndex(source, 0, null);
    }

    var max_dimension: i64 = policy.max_stored_dimension;
    const max_number = CFNumberCreate(
        null,
        kCFNumberSInt64Type,
        @ptrCast(&max_dimension),
    ) orelse return null;
    defer release(max_number);

    const keys = [_]?*const anyopaque{
        @ptrCast(kCGImageSourceCreateThumbnailFromImageAlways),
        @ptrCast(kCGImageSourceCreateThumbnailWithTransform),
        @ptrCast(kCGImageSourceThumbnailMaxPixelSize),
    };
    const values = [_]?*const anyopaque{
        @ptrCast(kCFBooleanTrue),
        @ptrCast(kCFBooleanTrue),
        @ptrCast(max_number),
    };
    const options = CFDictionaryCreate(
        null,
        &keys,
        &values,
        keys.len,
        null,
        null,
    ) orelse return null;
    defer release(options);

    return CGImageSourceCreateThumbnailAtIndex(source, 0, options);
}

fn encodeJpeg(
    comptime Artwork: type,
    comptime Format: type,
    allocator: std.mem.Allocator,
    image: CGImageRef,
) std.mem.Allocator.Error!?Artwork {
    const width = std.math.cast(u32, CGImageGetWidth(image)) orelse return null;
    const height = std.math.cast(u32, CGImageGetHeight(image)) orelse return null;
    if (!policy.dimensionsAllowed(width, height)) return null;
    if (width > policy.max_stored_dimension or height > policy.max_stored_dimension) return null;

    const output = CFDataCreateMutable(null, 0) orelse return null;
    defer release(output);
    const jpeg_type = CFStringCreateWithCString(
        null,
        "public.jpeg",
        kCFStringEncodingUTF8,
    ) orelse return null;
    defer release(jpeg_type);

    const destination = CGImageDestinationCreateWithData(output, jpeg_type, 1, null) orelse
        return null;
    defer release(destination);
    CGImageDestinationAddImage(destination, image, null);
    if (!CGImageDestinationFinalize(destination)) return null;

    const length = CFDataGetLength(output);
    if (length <= 0 or length > policy.max_encoded_bytes) return null;
    const byte_len: usize = @intCast(length);
    const bytes = CFDataGetBytePtr(output) orelse return null;

    return .{
        .format = Format.jpeg,
        .bytes = try allocator.dupe(u8, bytes[0..byte_len]),
        .width = width,
        .height = height,
    };
}
