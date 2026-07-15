const std = @import("std");

const control = @import("../control.zig");
const library = @import("../library/service.zig");
const playback = @import("../playback.zig");
const codec = @import("codec.zig");

const c = @cImport({
    @cInclude("grpc/byte_buffer.h");
    @cInclude("grpc/byte_buffer_reader.h");
    @cInclude("grpc/credentials.h");
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/grpc_security.h");
    @cInclude("grpc/slice.h");
    @cInclude("grpc/support/time.h");
});

pub const service_full_name = control.service_full_name_z;

pub const InitToken = struct {
    pub fn init() InitToken {
        c.grpc_init();
        return .{};
    }

    pub fn deinit(_: InitToken) void {
        c.grpc_shutdown();
    }
};

pub const ServerConfig = struct {
    address: [:0]const u8 = "127.0.0.1:5779",
};

pub const Server = struct {
    init_token: InitToken,
    cq: *c.grpc_completion_queue,
    server: *c.grpc_server,

    pub fn init(config: ServerConfig) !Server {
        const init_token = InitToken.init();
        errdefer init_token.deinit();

        const cq = c.grpc_completion_queue_create_for_next(null) orelse
            return error.GrpcCompletionQueueCreateFailed;
        errdefer c.grpc_completion_queue_destroy(cq);

        const server = c.grpc_server_create(null, null) orelse
            return error.GrpcServerCreateFailed;
        errdefer c.grpc_server_destroy(server);

        c.grpc_server_register_completion_queue(server, cq, null);

        const credentials = c.grpc_insecure_server_credentials_create() orelse
            return error.GrpcCredentialsCreateFailed;
        defer c.grpc_server_credentials_release(credentials);

        const bound_port = c.grpc_server_add_http2_port(
            server,
            config.address.ptr,
            credentials,
        );
        if (bound_port == 0) return error.GrpcBindFailed;

        c.grpc_server_start(server);

        return .{
            .init_token = init_token,
            .cq = cq,
            .server = server,
        };
    }

    pub fn deinit(self: *Server) void {
        var shutdown_tag: u8 = 0;
        const shutdown_tag_ptr: *anyopaque = @ptrCast(&shutdown_tag);
        c.grpc_server_shutdown_and_notify(self.server, self.cq, shutdown_tag_ptr);

        while (true) {
            const event = c.grpc_completion_queue_next(
                self.cq,
                c.gpr_inf_future(c.GPR_CLOCK_REALTIME),
                null,
            );
            if (event.type == c.GRPC_OP_COMPLETE and event.tag == shutdown_tag_ptr) {
                break;
            }
            if (event.type == c.GRPC_QUEUE_SHUTDOWN) {
                break;
            }
        }

        c.grpc_server_destroy(self.server);

        c.grpc_completion_queue_shutdown(self.cq);
        while (true) {
            const event = c.grpc_completion_queue_next(
                self.cq,
                c.gpr_inf_future(c.GPR_CLOCK_REALTIME),
                null,
            );
            if (event.type == c.GRPC_QUEUE_SHUTDOWN) break;
        }
        c.grpc_completion_queue_destroy(self.cq);

        self.init_token.deinit();
    }

    pub fn requestCall(
        self: *Server,
        call: *IncomingCall,
        tag: *anyopaque,
    ) void {
        _ = c.grpc_server_request_call(
            self.server,
            &call.call,
            &call.details,
            &call.request_metadata,
            self.cq,
            self.cq,
            tag,
        );
    }

    pub fn next(self: *Server, deadline: c.gpr_timespec) c.grpc_event {
        return c.grpc_completion_queue_next(self.cq, deadline, null);
    }

    pub fn runUnaryControlLoop(
        self: *Server,
        allocator: std.mem.Allocator,
        controller: *playback.Controller,
        library_service: *const library.Service,
    ) ControlLoopError!void {
        while (true) {
            var incoming = IncomingCall.init();
            defer incoming.deinit();

            const accept_event = try self.acceptCall(&incoming);
            if (accept_event.success == 0) continue;

            try self.handleUnaryControlCall(
                allocator,
                controller,
                library_service,
                &incoming,
            );
        }
    }

    fn handleUnaryControlCall(
        self: *Server,
        allocator: std.mem.Allocator,
        controller: *playback.Controller,
        library_service: *const library.Service,
        incoming: *IncomingCall,
    ) ControlLoopError!void {
        const call = incoming.call.?;

        const payload = self.receiveUnaryPayload(allocator, call) catch |err| {
            return switch (err) {
                error.Cancelled => {},
                error.MissingRequestMessage => self.sendStatus(
                    call,
                    c.GRPC_STATUS_INVALID_ARGUMENT,
                    "missing request message",
                ),
                error.InvalidByteBuffer => self.sendStatus(
                    call,
                    c.GRPC_STATUS_INVALID_ARGUMENT,
                    "invalid request message",
                ),
                error.OutOfMemory => error.OutOfMemory,
                error.Failed => error.Failed,
                error.Shutdown => error.Shutdown,
            };
        };
        defer allocator.free(payload);

        const method = incoming.method();
        const request = codec.decodeRequest(method, payload) catch |err| {
            const status = mapDecodeError(err);
            return self.sendStatus(call, status, decodeErrorDetail(err));
        };

        const command = switch (request) {
            .command => |command| command,
            .watch => return self.sendStatus(
                call,
                c.GRPC_STATUS_UNIMPLEMENTED,
                "watch is not implemented",
            ),
            .list_tracks => |list_request| {
                var page = library_service.listTracks(
                    allocator,
                    list_request,
                ) catch |err| {
                    const mapped = mapLibraryError(err);
                    return self.sendStatus(call, mapped.status, mapped.detail);
                };
                defer page.deinit(allocator);

                const response_payload = codec.encodeListTracksResponse(
                    allocator,
                    page,
                ) catch {
                    return self.sendStatus(
                        call,
                        c.GRPC_STATUS_RESOURCE_EXHAUSTED,
                        "response allocation failed",
                    );
                };
                defer allocator.free(response_payload);

                return self.sendMessage(
                    call,
                    response_payload,
                    c.GRPC_STATUS_OK,
                    "ok",
                );
            },
        };

        const response = controller.execute(command) catch |err| {
            const mapped = mapExecuteError(err);
            return self.sendStatus(call, mapped.status, mapped.detail);
        };

        const response_payload = codec.encodeResponse(allocator, response) catch {
            return self.sendStatus(
                call,
                c.GRPC_STATUS_RESOURCE_EXHAUSTED,
                "response allocation failed",
            );
        };
        defer allocator.free(response_payload);

        return self.sendMessage(
            call,
            response_payload,
            c.GRPC_STATUS_OK,
            "ok",
        );
    }

    fn acceptCall(
        self: *Server,
        incoming: *IncomingCall,
    ) ControlLoopError!c.grpc_event {
        var tag: u8 = 0;
        self.requestCall(incoming, &tag);
        return self.waitForTag(&tag);
    }

    fn receiveUnaryPayload(
        self: *Server,
        allocator: std.mem.Allocator,
        call: *c.grpc_call,
    ) ReceivePayloadError![]u8 {
        var request_payload: ?*c.grpc_byte_buffer = null;

        var ops = receiveUnaryPayloadOps(&request_payload);
        const event = try self.runBatch(call, ops[0..]);
        if (event.success == 0) {
            return error.Cancelled;
        }

        const payload_buffer = request_payload orelse
            return error.MissingRequestMessage;
        defer c.grpc_byte_buffer_destroy(payload_buffer);

        return readByteBuffer(allocator, payload_buffer);
    }

    fn sendStatus(
        self: *Server,
        call: *c.grpc_call,
        status: c.grpc_status_code,
        detail: [:0]const u8,
    ) ControlLoopError!void {
        return self.sendMessage(call, "", status, detail);
    }

    fn sendMessage(
        self: *Server,
        call: *c.grpc_call,
        message: []const u8,
        status: c.grpc_status_code,
        detail: [:0]const u8,
    ) ControlLoopError!void {
        var status_detail = c.grpc_slice_from_static_string(detail.ptr);
        defer c.grpc_slice_unref(status_detail);

        var send_ops = zeroedGrpcOps(3);
        send_ops[0].op = c.GRPC_OP_SEND_INITIAL_METADATA;

        var op_count: usize = 2;
        var response_buffer: ?*c.grpc_byte_buffer = null;
        if (message.len != 0) {
            var slice = c.grpc_slice_from_copied_buffer(
                @ptrCast(message.ptr),
                message.len,
            );
            defer c.grpc_slice_unref(slice);

            response_buffer = c.grpc_raw_byte_buffer_create(&slice, 1) orelse
                return error.Failed;
            send_ops[1].op = c.GRPC_OP_SEND_MESSAGE;
            send_ops[1].data.send_message.send_message = response_buffer.?;
            op_count = 3;
        }
        defer if (response_buffer) |buffer| c.grpc_byte_buffer_destroy(buffer);

        const status_index = op_count - 1;
        send_ops[status_index].op = c.GRPC_OP_SEND_STATUS_FROM_SERVER;
        send_ops[status_index].data.send_status_from_server.status = status;
        send_ops[status_index].data.send_status_from_server.status_details =
            &status_detail;

        _ = try self.runBatch(call, send_ops[0..op_count]);
    }

    fn runBatch(
        self: *Server,
        call: *c.grpc_call,
        ops: []c.grpc_op,
    ) ControlLoopError!c.grpc_event {
        var tag: u8 = 0;
        try startBatch(call, ops, &tag);
        return self.waitForTag(&tag);
    }

    fn waitForTag(
        self: *Server,
        tag: *anyopaque,
    ) ControlLoopError!c.grpc_event {
        while (true) {
            const event = self.next(c.gpr_inf_future(c.GPR_CLOCK_REALTIME));
            switch (event.type) {
                c.GRPC_OP_COMPLETE => {
                    if (event.tag == tag) return event;
                    return error.Failed;
                },
                c.GRPC_QUEUE_SHUTDOWN => return error.Shutdown,
                c.GRPC_QUEUE_TIMEOUT => continue,
                else => return error.Failed,
            }
        }
    }
};

pub const ControlLoopError = std.mem.Allocator.Error || error{
    Failed,
    Shutdown,
};

const ReceivePayloadError = ControlLoopError || error{
    Cancelled,
    MissingRequestMessage,
    InvalidByteBuffer,
};

pub const IncomingCall = struct {
    call: ?*c.grpc_call = null,
    details: c.grpc_call_details = undefined,
    request_metadata: c.grpc_metadata_array = undefined,

    pub fn init() IncomingCall {
        var self = IncomingCall{};
        c.grpc_call_details_init(&self.details);
        c.grpc_metadata_array_init(&self.request_metadata);
        return self;
    }

    pub fn deinit(self: *IncomingCall) void {
        if (self.call) |call| c.grpc_call_unref(call);
        c.grpc_call_details_destroy(&self.details);
        c.grpc_metadata_array_destroy(&self.request_metadata);
    }

    pub fn methodSlice(self: *const IncomingCall) c.grpc_slice {
        return self.details.method;
    }

    fn method(self: *const IncomingCall) []const u8 {
        return sliceBytes(self.methodSlice());
    }
};

fn startBatch(
    call: *c.grpc_call,
    ops: []c.grpc_op,
    tag: *anyopaque,
) ControlLoopError!void {
    if (c.grpc_call_start_batch(
        call,
        ops.ptr,
        ops.len,
        tag,
        null,
    ) != c.GRPC_CALL_OK) {
        return error.Failed;
    }
}

fn receiveUnaryPayloadOps(
    request_payload: *?*c.grpc_byte_buffer,
) [1]c.grpc_op {
    var ops = zeroedGrpcOps(1);

    ops[0].op = c.GRPC_OP_RECV_MESSAGE;
    ops[0].data.recv_message.recv_message = request_payload;

    return ops;
}

fn zeroedGrpcOps(comptime count: usize) [count]c.grpc_op {
    return [_]c.grpc_op{std.mem.zeroes(c.grpc_op)} ** count;
}

fn readByteBuffer(
    allocator: std.mem.Allocator,
    buffer: *c.grpc_byte_buffer,
) (std.mem.Allocator.Error || error{InvalidByteBuffer})![]u8 {
    var reader: c.grpc_byte_buffer_reader = undefined;
    if (c.grpc_byte_buffer_reader_init(&reader, buffer) == 0) {
        return error.InvalidByteBuffer;
    }
    defer c.grpc_byte_buffer_reader_destroy(&reader);

    const slice = c.grpc_byte_buffer_reader_readall(&reader);
    defer c.grpc_slice_unref(slice);

    return allocator.dupe(u8, sliceBytes(slice));
}

fn sliceBytes(slice: c.grpc_slice) []const u8 {
    if (slice.refcount != null) {
        const ptr: [*]const u8 = @ptrCast(slice.data.refcounted.bytes);
        return ptr[0..slice.data.refcounted.length];
    }

    return slice.data.inlined.bytes[0..slice.data.inlined.length];
}

const MappedStatus = struct {
    status: c.grpc_status_code,
    detail: [:0]const u8,
};

const ExecuteError = std.mem.Allocator.Error || control.ControlError;

fn mapDecodeError(err: codec.DecodeError) c.grpc_status_code {
    return switch (err) {
        error.InvalidMethod => c.GRPC_STATUS_UNIMPLEMENTED,
        else => c.GRPC_STATUS_INVALID_ARGUMENT,
    };
}

fn decodeErrorDetail(err: codec.DecodeError) [:0]const u8 {
    return switch (err) {
        error.InvalidMethod => "method is not implemented",
        else => "invalid control request",
    };
}

fn mapExecuteError(
    err: ExecuteError,
) MappedStatus {
    return switch (err) {
        error.OutOfMemory => .{
            .status = c.GRPC_STATUS_RESOURCE_EXHAUSTED,
            .detail = "allocation failed",
        },
        error.PlaybackNotFound => .{
            .status = c.GRPC_STATUS_NOT_FOUND,
            .detail = "playback not found",
        },
        error.InvalidState => .{
            .status = c.GRPC_STATUS_FAILED_PRECONDITION,
            .detail = "invalid playback state",
        },
        error.UnsupportedOperation => .{
            .status = c.GRPC_STATUS_UNIMPLEMENTED,
            .detail = "control operation is not implemented",
        },
    };
}

fn mapLibraryError(err: library.Error) MappedStatus {
    return switch (err) {
        error.InvalidPageSize, error.InvalidPageToken => .{
            .status = c.GRPC_STATUS_INVALID_ARGUMENT,
            .detail = "invalid library page request",
        },
        error.DatabaseBusy => .{
            .status = c.GRPC_STATUS_UNAVAILABLE,
            .detail = "library database is busy",
        },
        error.OutOfMemory => .{
            .status = c.GRPC_STATUS_RESOURCE_EXHAUSTED,
            .detail = "allocation failed",
        },
        error.DatabaseConstraint,
        error.DatabaseOpenFailed,
        error.DatabaseOperationFailed,
        error.InvalidScan,
        => .{
            .status = c.GRPC_STATUS_INTERNAL,
            .detail = "library database operation failed",
        },
    };
}

test "maps control errors to grpc statuses inside the adapter" {
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_NOT_FOUND)),
        mapExecuteError(error.PlaybackNotFound).status,
    );
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_FAILED_PRECONDITION)),
        mapExecuteError(error.InvalidState).status,
    );
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_UNIMPLEMENTED)),
        mapExecuteError(error.UnsupportedOperation).status,
    );
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_RESOURCE_EXHAUSTED)),
        mapExecuteError(error.OutOfMemory).status,
    );
}

test "maps malformed control requests to grpc statuses inside the adapter" {
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_UNIMPLEMENTED)),
        mapDecodeError(error.InvalidMethod),
    );
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_INVALID_ARGUMENT)),
        mapDecodeError(error.TruncatedMessage),
    );
}

test "maps library errors to grpc statuses inside the adapter" {
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_INVALID_ARGUMENT)),
        mapLibraryError(error.InvalidPageToken).status,
    );
    try std.testing.expectEqual(
        @as(c.grpc_status_code, @intCast(c.GRPC_STATUS_UNAVAILABLE)),
        mapLibraryError(error.DatabaseBusy).status,
    );
}
