const control = @import("../control.zig");

const c = @cImport({
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/grpc_security.h");
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

        const bound_port = c.grpc_server_add_insecure_http2_port(
            server,
            config.address.ptr,
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
        c.grpc_server_shutdown_and_notify(self.server, self.cq, &shutdown_tag);

        while (true) {
            const event = c.grpc_completion_queue_next(
                self.cq,
                c.gpr_inf_future(c.GPR_CLOCK_REALTIME),
                null,
            );
            if (event.type == c.GRPC_OP_COMPLETE and event.tag == &shutdown_tag) {
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
        c.grpc_server_request_call(
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
};
