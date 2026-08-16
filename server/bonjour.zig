const std = @import("std");
const stdout = @import("stdout");
const posix = std.posix;

const DNSServiceErrorType = i32;
const kDNSServiceErr_NoError: DNSServiceErrorType = 0;

const DNSServiceRefImpl = opaque {};
const DNSServiceRef = *DNSServiceRefImpl;

const DNSServiceRegisterReply = *const fn (
    service: DNSServiceRef,
    flags: u32,
    error_code: i32,
    name: [*c]const u8,
    regtype: [*c]const u8,
    domain: [*c]const u8,
    context: ?*anyopaque,
) callconv(.c) void;

extern fn DNSServiceRegister(
    service: *DNSServiceRef,
    flags: u32,
    interfaceIndex: u32,
    name: [*c]const u8,
    regtype: [*c]const u8,
    domain: [*c]const u8,
    host: [*c]const u8,
    port: u16,
    txtLen: u16,
    txtRecord: ?*const anyopaque,
    callBack: DNSServiceRegisterReply,
    context: ?*anyopaque,
) callconv(.c) i32;

extern fn DNSServiceRefSockFD(
    service: DNSServiceRef,
) callconv(.c) c_int;

extern fn DNSServiceProcessResult(
    service: DNSServiceRef,
) callconv(.c) i32;

extern fn DNSServiceRefDeallocate(
    service: DNSServiceRef,
) callconv(.c) void;

pub fn registerBonjourService() !void {
    var service_ref: DNSServiceRef = undefined;

    const listener_server_port: u16 = 5778;
    const port_network_order = std.mem.nativeToBig(u16, listener_server_port);
    const txt_record = "\x0egrpc-port=5779";

    const err = DNSServiceRegister(
        &service_ref,
        0,
        0,
        "ListenerMusicServer",
        "_lstn._tcp",
        null,
        null,
        port_network_order,
        @intCast(txt_record.len),
        @ptrCast(txt_record.ptr),
        registrationCallback,
        null,
    );

    if (err != kDNSServiceErr_NoError) {
        stdout.printGlobal("Error registering service: {d}\n", .{err});
        return error.BonjourFailed;
    }
    defer DNSServiceRefDeallocate(service_ref);

    const fd = DNSServiceRefSockFD(service_ref);
    if (fd < 0) return error.BonjourInvalidSocket;

    var poll_fds = [_]posix.pollfd{
        .{
            .fd = fd,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    while (true) {
        const ready_count = try posix.poll(&poll_fds, -1);

        if (ready_count > 0) {
            if (poll_fds[0].revents & posix.POLL.IN != 0) {
                _ = DNSServiceProcessResult(service_ref);
            }
        }
    }
}

fn registrationCallback(
    _: DNSServiceRef,
    _: u32,
    error_code: i32,
    name: [*c]const u8,
    _: [*c]const u8,
    _: [*c]const u8,
    _: ?*anyopaque,
) callconv(.c) void {
    if (error_code == kDNSServiceErr_NoError) {
        stdout.printGlobal("Successfully registered as: {s} \n", .{name});
    } else {
        stdout.printGlobal("Error registering bonjour service: {s}\nCode:{d}", .{ name, error_code });
    }
}
