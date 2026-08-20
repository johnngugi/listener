const std = @import("std");
const stdout = @import("stdout");
const posix = std.posix;

const playback_event = @import("playback_event.zig");

const DNSServiceErrorType = i32;
const kDNSServiceErr_NoError: DNSServiceErrorType = 0;

const kDNSServiceFlagsAdd = 0x2;
const discovery_poll_interval_ms = 100;
const discovery_timeout_ms = 3000;

const DNSServiceRefImpl = opaque {};
const DNSServiceRef = *DNSServiceRefImpl;

const DNSServiceBrowseReply = *const fn (
    service: DNSServiceRef,
    flags: u32,
    interface_index: u32,
    error_code: DNSServiceErrorType,
    service_name: [*c]const u8,
    regtype: [*c]const u8,
    reply_domain: [*c]const u8,
    context: ?*anyopaque,
) callconv(.c) void;

const DNSServiceResolveReply = *const fn (
    service: DNSServiceRef,
    flags: u32,
    interface_index: u32,
    error_code: DNSServiceErrorType,
    full_name: [*c]const u8,
    host_target: [*c]const u8,
    port: u16,
    txt_len: u16,
    txt_record: [*c]const u8,
    context: ?*anyopaque,
) callconv(.c) void;

extern fn DNSServiceBrowse(
    service: *DNSServiceRef,
    flags: u32,
    interface_index: u32,
    regtype: [*c]const u8,
    domain: [*c]const u8,
    callBack: DNSServiceBrowseReply,
    context: ?*anyopaque,
) callconv(.c) DNSServiceErrorType;

extern fn DNSServiceRefDeallocate(
    service: DNSServiceRef,
) callconv(.c) void;

extern fn DNSServiceRefSockFD(
    service: DNSServiceRef,
) callconv(.c) c_int;

extern fn DNSServiceProcessResult(
    service: DNSServiceRef,
) callconv(.c) i32;

extern fn DNSServiceResolve(
    service: *DNSServiceRef,
    flags: u32,
    interface_index: u32,
    service_name: [*c]const u8,
    regtype: [*c]const u8,
    domain: [*c]const u8,
    callBack: DNSServiceResolveReply,
    context: ?*anyopaque,
) callconv(.c) DNSServiceErrorType;

const ActiveService = struct {
    fd: i32,
    service: DNSServiceRef,
};

const BonjourState = struct {
    poll_fds: std.ArrayList(posix.pollfd),
    services: std.ArrayList(ActiveService),
    event_callback: playback_event.PlaybackEventCallback,
    allocator: std.mem.Allocator,
    resolved: bool = false,

    fn add(self: *BonjourState, fd: i32, ref: DNSServiceRef) void {
        const poll_fd: posix.pollfd = .{
            .fd = fd,
            .events = posix.POLL.IN,
            .revents = 0,
        };
        const active_service: ActiveService = .{
            .fd = fd,
            .service = ref,
        };

        self.poll_fds.appendAssumeCapacity(poll_fd);
        self.services.appendAssumeCapacity(active_service);
    }

    fn remove(self: *BonjourState, fd: i32) void {
        for (self.poll_fds.items, 0..) |poll_fd, i| {
            if (poll_fd.fd == fd) {
                _ = self.poll_fds.swapRemove(i);
                break;
            }
        }

        for (self.services.items, 0..) |service, i| {
            if (service.fd == fd) {
                _ = self.services.swapRemove(i);
                break;
            }
        }
    }

    pub fn getRef(self: *BonjourState, fd: i32) ?DNSServiceRef {
        for (self.services.items) |service| {
            if (service.fd == fd) {
                return service.service;
            }
        }

        return null;
    }
};

pub fn findListenerService(
    allocator: std.mem.Allocator,
    discover_callback: playback_event.PlaybackEventCallback,
    stop_requested: *const std.atomic.Value(bool),
) !void {
    const poll_fds = try std.ArrayList(posix.pollfd).initCapacity(allocator, 10);
    const services = try std.ArrayList(ActiveService).initCapacity(allocator, 10);

    var state: BonjourState = .{
        .poll_fds = poll_fds,
        .services = services,
        .event_callback = discover_callback,
        .allocator = allocator,
    };
    defer state.poll_fds.deinit(allocator);
    defer state.services.deinit(allocator);

    var service_ref: DNSServiceRef = undefined;
    const err = DNSServiceBrowse(
        &service_ref,
        0,
        0,
        "_lstn._tcp",
        null,
        browseCallback,
        &state,
    );

    if (err != kDNSServiceErr_NoError) {
        stdout.printGlobal("Error browsing service: {d}\n", .{err});
        return error.BonjourFailed;
    }
    defer DNSServiceRefDeallocate(service_ref);

    const fd = DNSServiceRefSockFD(service_ref);
    if (fd < 0) return error.BonjourInvalidSocket;

    state.add(fd, service_ref);

    var idle_ms: u32 = 0;
    while (!state.resolved) {
        if (stop_requested.load(.acquire)) return;

        const ready_count = try posix.poll(
            state.poll_fds.items,
            discovery_poll_interval_ms,
        );

        if (stop_requested.load(.acquire)) return;

        if (ready_count == 0) {
            idle_ms += discovery_poll_interval_ms;
            if (idle_ms >= discovery_timeout_ms) {
                return error.ListenerServiceNotFound;
            }

            continue;
        }

        idle_ms = 0;

        if (ready_count > 0) {
            for (state.poll_fds.items) |pfd| {
                if ((pfd.revents & posix.POLL.IN) != 0) {
                    if (state.getRef(pfd.fd)) |ref| {
                        _ = DNSServiceProcessResult(ref);
                    }

                    break;
                }
            }
        }
    }
}

fn browseCallback(
    _: DNSServiceRef,
    flags: u32,
    interface_index: u32,
    error_code: DNSServiceErrorType,
    service_name: [*c]const u8,
    regtype: [*c]const u8,
    reply_domain: [*c]const u8,
    context: ?*anyopaque,
) callconv(.c) void {
    if (error_code != kDNSServiceErr_NoError) {
        stdout.printGlobal("Browse failed with error: {d}\n", .{error_code});
        return;
    }

    const state: *BonjourState = @ptrCast(@alignCast(context));

    if ((flags & kDNSServiceFlagsAdd) != 0) {
        stdout.printGlobal("Found music server: {s}\n", .{service_name});

        var resolve_ref: DNSServiceRef = undefined;
        const err = DNSServiceResolve(
            &resolve_ref,
            0,
            interface_index,
            service_name,
            regtype,
            reply_domain,
            resolveCallback,
            context,
        );

        if (err == kDNSServiceErr_NoError) {
            const fd = DNSServiceRefSockFD(resolve_ref);

            state.add(fd, resolve_ref);
        }
    } else {
        stdout.printGlobal("Music server disappeared: {s}\n", .{service_name});
    }
}

export fn resolveCallback(
    service: DNSServiceRef,
    _: u32,
    _: u32,
    error_code: DNSServiceErrorType,
    full_name: [*c]const u8,
    host_target: [*c]const u8,
    port: u16,
    txt_len: u16,
    _: [*c]const u8,
    context: ?*anyopaque,
) callconv(.c) void {
    if (error_code != kDNSServiceErr_NoError) {
        stdout.printGlobal("Resolve failed with error: {d}\n", .{error_code});
        return;
    }

    const state: *BonjourState = @ptrCast(@alignCast(context));

    const native_port = std.mem.bigToNative(u16, port);

    std.debug.print("Resolved Server: {s}\n", .{full_name});
    std.debug.print("Target Hostname: {s}\n", .{host_target});
    std.debug.print("Port: {d}\n", .{native_port});

    const discovered_service = state.allocator.create(playback_event.DiscoveredService) catch |err| {
        stdout.printGlobal("Resolve failed with error: {}\n", .{err});
        return;
    };

    const full_name_copy = state.allocator.dupe(u8, std.mem.span(full_name)) catch |err| {
        state.allocator.destroy(discovered_service);
        stdout.printGlobal("Resolve failed with error: {}\n", .{err});
        return;
    };
    const host_name_copy = state.allocator.dupe(u8, std.mem.span(host_target)) catch |err| {
        state.allocator.free(full_name_copy);
        state.allocator.destroy(discovered_service);
        stdout.printGlobal("Resolve failed with error: {}\n", .{err});
        return;
    };

    discovered_service.*.full_name = full_name_copy.ptr;
    discovered_service.*.full_name_len = full_name_copy.len;
    discovered_service.*.host_target = host_name_copy.ptr;
    discovered_service.*.host_target_len = host_name_copy.len;
    discovered_service.*.port = native_port;

    state.event_callback(
        @ptrCast(discovered_service),
        @intFromEnum(playback_event.PlaybackEvent.discovered_service),
    );

    // 2. The TXT record is raw bytes, not a string
    if (txt_len > 0) {
        std.debug.print("Contains {d} bytes of TXT metadata.\n", .{txt_len});
        // You would use c.TXTRecordGetValuePtr() here to extract keys
    }

    const fd = DNSServiceRefSockFD(service);

    // 3. We have the data, so we can kill the resolve operation
    // This stops it from updating us if the TXT record changes later
    DNSServiceRefDeallocate(service);

    state.remove(fd);
    state.resolved = true;
}
