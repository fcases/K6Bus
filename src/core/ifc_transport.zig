// transport_crtp_example.zig
//
// Experimento de arquitectura:
//
// - ifcTransport:
//      interfaz dinámica para listas heterogéneas de transportes.
//
// - Transport(Self):
//      comportamiento común estilo CRTP. No tiene estado propio.
//      Todo el estado vive en el transporte concreto.
//
// - LoopTransport:
//      ejemplo concreto sencillo.
//      Implementa únicamente lo específico:
//          - fake network queue
//          - onSendBytes()
//          - onReceiveLoop()
//          - onCloseResources()
//          - onDeinit()
//
// Compilar orientativo:
//      zig build-exe transport_crtp_example.zig
//

const std = @import("std");

// ============================================================================
// TIPOS DE EJEMPLO
// ============================================================================

const Msg = struct {
    id: u32,
    payload: []const u8,
};

const Packet = struct {
    messages: []Msg,

    pub fn serialize(
        allocator: std.mem.Allocator,
        messages: []const Msg,
    ) ![]u8 {
        _ = &allocator;

        // Demo simple:
        // En K6Bus real aquí iría:
        //
        //      MsgList -> Packet -> seriigiAlBin()
        //
        var total: usize = 0;

        for (messages) |msg| {
            total += msg.payload.len;
            total += 1;
        }

        var out =
            try allocator.alloc(
                u8,
                total,
            );

        var index: usize = 0;

        for (messages) |msg| {
            @memcpy(
                out[index .. index + msg.payload.len],
                msg.payload,
            );

            index += msg.payload.len;

            out[index] = '\n';
            index += 1;
        }

        return out;
    }

    pub fn deserialize(
        allocator: std.mem.Allocator,
        bytes: []const u8,
    ) ![]Msg {
        // Demo simple:
        // En K6Bus real aquí iría:
        //
        //      WireBytes -> Packet.deseriigiElBin()
        //
        var list: std.ArrayList(Msg) = .empty;
        errdefer list.deinit(allocator);

        var it =
            std.mem.splitScalar(
                u8,
                bytes,
                '\n',
            );

        var id: u32 = 0;

        while (it.next()) |part| {
            if (part.len == 0)
                continue;

            const copy =
                try allocator.dupe(
                    u8,
                    part,
                );

            try list.append(
                allocator,
                .{
                    .id = id,
                    .payload = copy,
                },
            );

            id += 1;
        }

        return try list.toOwnedSlice(allocator);
    }
};

fn freeMsgs(
    allocator: std.mem.Allocator,
    msgs: []Msg,
) void {
    for (msgs) |msg| {
        allocator.free(msg.payload);
    }

    allocator.free(msgs);
}

// ============================================================================
// DOMINIO DE EJEMPLO
// ============================================================================

const Domain = struct {
    allocator: std.mem.Allocator,
    running: bool = false,

    transports: std.ArrayList(ifcTransport) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
    ) Domain {
        return .{
            .allocator = allocator,
            .running = false,
        };
    }

    pub fn deinit(self: *Domain) void {
        self.transports.deinit(self.allocator);
    }

    pub fn addTransport(
        self: *Domain,
        t: ifcTransport,
    ) !void {
        try self.transports.append(
            self.allocator,
            t,
        );
    }

    pub fn start(self: *Domain) !void {
        self.running = true;

        for (self.transports.items) |t| {
            try t.start();
        }
    }

    pub fn close(self: *Domain) void {
        //
        // Filosofía K6Bus actual:
        //
        //      close() = fast shutdown
        //
        self.running = false;

        for (self.transports.items) |t| {
            t.close();
        }
    }

    pub fn onMsgListReceived(
        self: *Domain,
        msgs: []Msg,
    ) void {
        defer freeMsgs(
            self.allocator,
            msgs,
        );

        std.debug.print(
            "[Domain] received {d} messages from UP\n",
            .{msgs.len},
        );

        for (msgs) |msg| {
            std.debug.print(
                "    msg id={d} payload={s}\n",
                .{
                    msg.id,
                    msg.payload,
                },
            );
        }
    }
};

// ============================================================================
// QUEUEMGR DE EJEMPLO
// ============================================================================

const QueueMgr = struct {
    allocator: std.mem.Allocator,

    owner: *anyopaque,
    dispatch_fn: *const fn (
        owner: *anyopaque,
        msg_list: []Msg,
    ) void,

    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    queue: std.ArrayList(Msg) = .empty,

    worker: ?std.Thread = null,

    running: bool = false,
    finished: bool = false,

    name: []const u8,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        owner: *anyopaque,
        dispatch_fn: *const fn (
            owner: *anyopaque,
            msg_list: []Msg,
        ) void,
    ) !Self {
        return .{
            .allocator = allocator,
            .owner = owner,
            .dispatch_fn = dispatch_fn,
            .name = try allocator.dupe(
                u8,
                name,
            ),
        };
    }

    pub fn start(self: *Self) !void {
        if (self.running)
            return;

        self.finished = false;
        self.running = true;

        self.worker =
            try std.Thread.spawn(
                .{},
                mainLoop,
                .{self},
            );

        std.debug.print(
            "[QueueMgr:{s}] started\n",
            .{self.name},
        );
    }

    pub fn enqueueMany(
        self: *Self,
        msgs: []Msg,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.finished) {
            freeMsgs(
                self.allocator,
                msgs,
            );

            return error.QueueClosed;
        }

        try self.queue.appendSlice(
            self.allocator,
            msgs,
        );

        //
        // La lista externa sólo contiene el array.
        // El ownership de cada Msg se transfiere a la cola.
        //
        self.allocator.free(msgs);

        self.cond.signal();
    }

    pub fn stop(self: *Self) void {
        if (!self.running)
            return;

        self.mutex.lock();
        self.finished = true;
        self.mutex.unlock();

        self.cond.broadcast();

        if (self.worker) |t| {
            t.join();
        }

        self.worker = null;
        self.running = false;

        std.debug.print(
            "[QueueMgr:{s}] stopped\n",
            .{self.name},
        );
    }

    pub fn close(self: *Self) void {
        self.stop();

        self.mutex.lock();

        if (self.queue.items.len > 0) {
            std.debug.print(
                "[QueueMgr:{s}] dropping {d} pending messages\n",
                .{
                    self.name,
                    self.queue.items.len,
                },
            );

            freeMsgs(
                self.allocator,
                self.queue.items,
            );

            self.queue = .empty;
        }

        self.mutex.unlock();

        self.queue.deinit(self.allocator);
        self.allocator.free(self.name);
    }

    fn mainLoop(self: *Self) void {
        while (true) {
            self.mutex.lock();

            while (self.queue.items.len == 0 and
                !self.finished)
            {
                self.cond.wait(&self.mutex);
            }

            if (self.finished and
                self.queue.items.len == 0)
            {
                self.mutex.unlock();
                break;
            }

            const count =
                self.queue.items.len;

            const batch =
                self.allocator.alloc(
                    Msg,
                    count,
                ) catch {
                    self.mutex.unlock();
                    continue;
                };

            @memcpy(
                batch,
                self.queue.items,
            );

            self.queue.clearRetainingCapacity();

            self.mutex.unlock();

            self.dispatch_fn(
                self.owner,
                batch,
            );
        }

        std.debug.print(
            "[QueueMgr:{s}] worker finished\n",
            .{self.name},
        );
    }
};

// ============================================================================
// INTERFACE DINÁMICA
// ============================================================================

const ifcTransport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        start: *const fn (*anyopaque) anyerror!void,
        stop: *const fn (*anyopaque) void,
        close: *const fn (*anyopaque) void,
        sendMsgs: *const fn (*anyopaque,[]Msg) anyerror!void,
    };

    pub fn start(self: ifcTransport) !void {
        try self.vtable.start(self.ptr);
    }

    pub fn stop(self: ifcTransport) void {
        self.vtable.stop(self.ptr);
    }

    pub fn close(self: ifcTransport) void {
        self.vtable.close(self.ptr);
    }

    pub fn sendMsgs(
        self: ifcTransport,
        msgs: []Msg,
    ) !void {
        try self.vtable.sendMsgs(
            self.ptr,
            msgs,
        );
    }

    pub fn init(impl: anytype) ifcTransport {
        const Impl =
            @TypeOf(impl.*);

        const gen = struct {
            fn start(ptr: *anyopaque) !void {
                const self: *Impl =
                    @ptrCast(@alignCast(ptr));

                try Transport(Impl).start(self);
            }

            fn stop(ptr: *anyopaque) void {
                const self: *Impl =
                    @ptrCast(@alignCast(ptr));

                Transport(Impl).stop(self);
            }

            fn close(ptr: *anyopaque) void {
                const self: *Impl =
                    @ptrCast(@alignCast(ptr));

                Transport(Impl).close(self);
            }

            fn sendMsgs(
                ptr: *anyopaque,
                msgs: []Msg,
            ) !void {
                const self: *Impl =
                    @ptrCast(@alignCast(ptr));

                try Transport(Impl).sendMsgs(
                    self,
                    msgs,
                );
            }
        };

        return .{
            .ptr = impl,
            .vtable = &.{
                .start = gen.start,
                .stop = gen.stop,
                .close = gen.close,
                .sendMsgs = gen.sendMsgs,
            },
        };
    }
};

// ============================================================================
// BASE COMÚN TIPO CRTP
// ============================================================================

fn Transport(comptime Self: type) type {
    return struct {
        // --------------------------------------------------------------------
        // LIFECYCLE
        // --------------------------------------------------------------------

        pub fn start(self: *Self) !void {
            if (self.running)
                return;

            self.running = true;

            try self.qm.start();

            if (@hasDecl(Self, "onStart")) {
                try self.onStart();
            }

            std.debug.print(
                "[Transport:{s}] started\n",
                .{self.name},
            );
        }

        pub fn stop(self: *Self) void {
            if (!self.running)
                return;

            self.running = false;

            //
            // Primer paso:
            // detener QueueMgr.
            //
            self.qm.stop();

            //
            // Segundo paso:
            // cerrar recursos específicos que puedan despertar hilos
            // bloqueados.
            //
            if (@hasDecl(Self, "onStop")) {
                self.onStop();
            }

            //
            // Tercer paso:
            // esperar hilos específicos.
            //
            joinRxThreadIfAny(self);

            std.debug.print(
                "[Transport:{s}] stopped\n",
                .{self.name},
            );
        }

        pub fn close(self: *Self) void {
            //
            // close() es cierre rápido.
            //
            self.running = false;

            //
            // 1. Cerrar actividad común.
            //
            self.qm.close();

            //
            // 2. Cerrar recursos específicos.
            //
            if (@hasDecl(Self, "onCloseResources")) {
                self.onCloseResources();
            }

            //
            // 3. Esperar hilos específicos.
            //
            joinRxThreadIfAny(self);

            //
            // 4. Cierre específico final.
            //    Aquí todavía NO se destruye memoria común fuera de Self.
            //
            if (@hasDecl(Self, "onClose")) {
                self.onClose();
            }

            //
            // 5. Liberar memoria común.
            //
            self.allocator.free(self.name);

            std.debug.print(
                "[Transport:{s}] closed\n",
                .{self.transport_kind_name},
            );

            //
            // 6. Destruir Self.
            //
            if (@hasDecl(Self, "onDeinit")) {
                self.onDeinit();
            }
        }

        fn joinRxThreadIfAny(self: *Self) void {
            if (@hasField(Self, "rx_thread")) {
                if (self.rx_thread) |t| {
                    t.join();
                }

                self.rx_thread = null;
            }
        }

        // --------------------------------------------------------------------
        // DOWN PATH
        // --------------------------------------------------------------------

        pub fn sendMsgs(
            self: *Self,
            msgs: []Msg,
        ) !void {
            //
            // En K6Bus real esto lo haría StreamQueueDOWN
            // encolando hacia el QueueMgr del transporte.
            //
            try self.qm.enqueueMany(msgs);
        }

        pub fn dispatchMsgList(
            owner: *anyopaque,
            msg_list: []Msg,
        ) void {
            const self: *Self =
                @ptrCast(@alignCast(owner));

            //
            // msg_list llega con ownership transferido desde QueueMgr.
            //
            const wire_bytes =
                Packet.serialize(
                    self.allocator,
                    msg_list,
                ) catch {
                    freeMsgs(
                        self.allocator,
                        msg_list,
                    );

                    return;
                };

            defer self.allocator.free(wire_bytes);

            //
            // Una vez serializado, liberamos mensajes originales.
            //
            freeMsgs(
                self.allocator,
                msg_list,
            );

            //
            // En el transporte concreto se implementa dónde van los bytes.
            //
            if (@hasDecl(Self, "onSendBytes")) {
                _ = self.onSendBytes(wire_bytes);
            }
        }

        // --------------------------------------------------------------------
        // UP PATH
        // --------------------------------------------------------------------

        pub fn receiveBytes(
            self: *Self,
            wire_bytes: []const u8,
        ) !void {
            if (!self.domain.running)
                return error.DomainClosed;

            const msgs =
                try Packet.deserialize(
                    self.allocator,
                    wire_bytes,
                );

            try dispatchUpstream(
                self,
                msgs,
            );
        }

        fn dispatchUpstream(
            self: *Self,
            msgs: []Msg,
        ) !void {
            if (!self.domain.running) {
                freeMsgs(
                    self.allocator,
                    msgs,
                );

                return error.DomainClosed;
            }

            //
            // En K6Bus real:
            //
            // 1. CrossConnectors
            // 2. Domain.onMsgListReceived()
            //
            self.domain.onMsgListReceived(msgs);
        }
    };
}

// ============================================================================
// LOOP TRANSPORT
// ============================================================================

const LoopTransport = struct {
    allocator: std.mem.Allocator,
    domain: *Domain,

    name: []const u8,
    transport_kind_name: []const u8 = "LoopTransport",

    running: bool = false,

    qm: QueueMgr,

    rx_thread: ?std.Thread = null,

    mutex: std.Thread.Mutex = .{},
    cond: std.Thread.Condition = .{},

    fake_network: std.ArrayList([]u8) = .empty,

    delay_ms: u32 = 10,

    const Self = @This();

    pub fn create(
        allocator: std.mem.Allocator,
        domain: *Domain,
        name: []const u8,
        delay_ms: u32,
    ) !*Self {
        const self =
            try allocator.create(Self);

        errdefer allocator.destroy(self);

        const name_copy =
            try allocator.dupe(
                u8,
                name,
            );

        const qm =
            try QueueMgr.init(
                allocator,
                name,
                self,
                Transport(Self).dispatchMsgList,
            );

        self.* = .{
            .allocator = allocator,
            .domain = domain,
            .name = name_copy,
            .qm = qm,
            .delay_ms = delay_ms,
        };

        return self;
    }

    // ------------------------------------------------------------------------
    // SPECIFIC START
    // ------------------------------------------------------------------------

    pub fn onStart(self: *Self) !void {
        self.rx_thread =
            try std.Thread.spawn(
                .{},
                rxMainLoop,
                .{self},
            );

        std.debug.print(
            "[LoopTransport] RX thread started\n",
            .{},
        );
    }

    // ------------------------------------------------------------------------
    // SPECIFIC STOP
    // ------------------------------------------------------------------------

    pub fn onStop(self: *Self) void {
        self.wakeRxLoop();

        std.debug.print(
            "[LoopTransport] stop requested\n",
            .{},
        );
    }

    // ------------------------------------------------------------------------
    // SPECIFIC CLOSE RESOURCES
    // ------------------------------------------------------------------------

    pub fn onCloseResources(self: *Self) void {
        //
        // No sockets.
        // Sólo despertar el hilo RX si está dormido.
        //
        self.wakeRxLoop();

        std.debug.print(
            "[LoopTransport] resources closed\n",
            .{},
        );
    }

    // ------------------------------------------------------------------------
    // SPECIFIC CLOSE
    // ------------------------------------------------------------------------

    pub fn onClose(self: *Self) void {
        self.mutex.lock();

        for (self.fake_network.items) |bytes| {
            self.allocator.free(bytes);
        }

        self.fake_network.deinit(self.allocator);

        self.mutex.unlock();

        std.debug.print(
            "[LoopTransport] fake network cleared\n",
            .{},
        );
    }

    // ------------------------------------------------------------------------
    // SPECIFIC DEINIT
    // ------------------------------------------------------------------------

    pub fn onDeinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    // ------------------------------------------------------------------------
    // SPECIFIC SEND
    // ------------------------------------------------------------------------

    pub fn onSendBytes(
        self: *Self,
        wire_bytes: []const u8,
    ) bool {
        const copy =
            self.allocator.dupe(
                u8,
                wire_bytes,
            ) catch return false;

        self.mutex.lock();
        defer self.mutex.unlock();

        self.fake_network.append(
            self.allocator,
            copy,
        ) catch {
            self.allocator.free(copy);
            return false;
        };

        self.cond.signal();

        std.debug.print(
            "[LoopTransport] queued {d} bytes to fake network\n",
            .{wire_bytes.len},
        );

        return true;
    }

    // ------------------------------------------------------------------------
    // RX LOOP
    // ------------------------------------------------------------------------

    fn rxMainLoop(self: *Self) void {
        while (true) {
            self.mutex.lock();

            while (self.fake_network.items.len == 0 and
                self.running)
            {
                self.cond.wait(&self.mutex);
            }

            if (!self.running and
                self.fake_network.items.len == 0)
            {
                self.mutex.unlock();
                break;
            }

            const bytes =
                self.fake_network.orderedRemove(0);

            self.mutex.unlock();

            std.Thread.sleep(
                @as(u64, self.delay_ms) *
                    std.time.ns_per_ms,
            );

            Transport(Self).receiveBytes(
                self,
                bytes,
            ) catch {};

            self.allocator.free(bytes);
        }

        std.debug.print(
            "[LoopTransport] RX thread finished\n",
            .{},
        );
    }

    fn wakeRxLoop(self: *Self) void {
        self.mutex.lock();
        self.cond.broadcast();
        self.mutex.unlock();
    }
};

// ============================================================================
// MAIN
// ============================================================================

pub fn main() !void {
    var gpa =
        std.heap.GeneralPurposeAllocator(
            .{
                .safety = true,
                .thread_safe = true,
            },
        ){};

    defer _ = gpa.deinit();

    const allocator =
        gpa.allocator();

    var domain =
        Domain.init(allocator);

    defer domain.deinit();

    const loop =
        try LoopTransport.create(
            allocator,
            &domain,
            "DefaultLoop_01",
            10,
        );

    const tr =
        ifcTransport.init(loop);

    try domain.addTransport(tr);

    try domain.start();

    var msgs =
        try allocator.alloc(
            Msg,
            2,
        );

    msgs[0] = .{
        .id = 1,
        .payload = try allocator.dupe(
            u8,
            "hola",
        ),
    };

    msgs[1] = .{
        .id = 2,
        .payload = try allocator.dupe(
            u8,
            "k6bus",
        ),
    };

    try tr.sendMsgs(msgs);

    std.Thread.sleep(
        100 * std.time.ns_per_ms,
    );

    domain.close();
}
