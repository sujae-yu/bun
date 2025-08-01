pub const Loop = uws.Loop;

/// Track if an object whose file descriptor is being watched should keep the event loop alive.
/// This is not reference counted. It only tracks active or inactive.
pub const KeepAlive = struct {
    status: Status = .inactive,

    const log = Output.scoped(.KeepAlive, false);

    const Status = enum { active, inactive, done };

    pub inline fn isActive(this: KeepAlive) bool {
        return this.status == .active;
    }

    /// Make calling ref() on this poll into a no-op.
    pub fn disable(this: *KeepAlive) void {
        this.unref(jsc.VirtualMachine.get());
        this.status = .done;
    }

    /// Only intended to be used from EventLoop.Pollable
    pub fn deactivate(this: *KeepAlive, loop: *Loop) void {
        if (this.status != .active)
            return;

        this.status = .inactive;
        loop.subActive(1);
    }

    /// Only intended to be used from EventLoop.Pollable
    pub fn activate(this: *KeepAlive, loop: *Loop) void {
        if (this.status != .inactive)
            return;

        this.status = .active;
        loop.addActive(1);
    }

    pub fn init() KeepAlive {
        return .{};
    }

    /// Prevent a poll from keeping the process alive.
    pub fn unref(this: *KeepAlive, event_loop_ctx_: anytype) void {
        if (this.status != .active)
            return;
        this.status = .inactive;

        if (comptime @TypeOf(event_loop_ctx_) == jsc.EventLoopHandle) {
            event_loop_ctx_.loop().unref();
            return;
        }
        const event_loop_ctx = jsc.AbstractVM(event_loop_ctx_);
        event_loop_ctx.platformEventLoop().unref();
    }

    /// From another thread, Prevent a poll from keeping the process alive.
    pub fn unrefConcurrently(this: *KeepAlive, vm: *jsc.VirtualMachine) void {
        if (this.status != .active)
            return;
        this.status = .inactive;
        vm.event_loop.unrefConcurrently();
    }

    /// Prevent a poll from keeping the process alive on the next tick.
    pub fn unrefOnNextTick(this: *KeepAlive, event_loop_ctx_: anytype) void {
        const event_loop_ctx = jsc.AbstractVM(event_loop_ctx_);
        if (this.status != .active)
            return;
        this.status = .inactive;
        // vm.pending_unref_counter +|= 1;
        event_loop_ctx.incrementPendingUnrefCounter();
    }

    /// From another thread, prevent a poll from keeping the process alive on the next tick.
    pub fn unrefOnNextTickConcurrently(this: *KeepAlive, vm: *jsc.VirtualMachine) void {
        if (this.status != .active)
            return;
        this.status = .inactive;
        _ = @atomicRmw(@TypeOf(vm.pending_unref_counter), &vm.pending_unref_counter, .Add, 1, .monotonic);
    }

    /// Allow a poll to keep the process alive.
    pub fn ref(this: *KeepAlive, event_loop_ctx_: anytype) void {
        if (this.status != .inactive)
            return;

        this.status = .active;
        const EventLoopContext = @TypeOf(event_loop_ctx_);
        if (comptime EventLoopContext == jsc.EventLoopHandle) {
            event_loop_ctx_.ref();
            return;
        }
        const event_loop_ctx = jsc.AbstractVM(event_loop_ctx_);
        event_loop_ctx.platformEventLoop().ref();
    }

    /// Allow a poll to keep the process alive.
    pub fn refConcurrently(this: *KeepAlive, vm: *jsc.VirtualMachine) void {
        if (this.status != .inactive)
            return;
        this.status = .active;
        vm.event_loop.refConcurrently();
    }

    pub fn refConcurrentlyFromEventLoop(this: *KeepAlive, loop: *jsc.EventLoop) void {
        this.refConcurrently(loop.virtual_machine);
    }

    pub fn unrefConcurrentlyFromEventLoop(this: *KeepAlive, loop: *jsc.EventLoop) void {
        this.unrefConcurrently(loop.virtual_machine);
    }
};

const KQueueGenerationNumber = if (Environment.isMac and Environment.allow_assert) usize else u0;
pub const FilePoll = struct {
    var max_generation_number: KQueueGenerationNumber = 0;

    fd: bun.FileDescriptor = invalid_fd,
    flags: Flags.Set = Flags.Set{},
    owner: Owner = Owner.Null,

    /// We re-use FilePoll objects to avoid allocating new ones.
    ///
    /// That means we might run into situations where the event is stale.
    /// on macOS kevent64 has an extra pointer field so we use it for that
    /// linux doesn't have a field like that
    generation_number: KQueueGenerationNumber = 0,
    next_to_free: ?*FilePoll = null,

    allocator_type: AllocatorType = .js,

    const ShellBufferedWriter = bun.shell.Interpreter.IOWriter.Poll;
    // const ShellBufferedWriter = bun.shell.Interpreter.WriterImpl;

    const FileReader = jsc.WebCore.FileReader;
    // const FIFO = jsc.WebCore.FIFO;
    // const FIFOMini = jsc.WebCore.FIFOMini;

    // const ShellBufferedWriterMini = bun.shell.InterpreterMini.BufferedWriter;
    // const ShellBufferedInput = bun.shell.ShellSubprocess.BufferedInput;
    // const ShellBufferedInputMini = bun.shell.SubprocessMini.BufferedInput;
    // const ShellSubprocessCapturedBufferedWriter = bun.shell.ShellSubprocess.BufferedOutput.CapturedBufferedWriter;
    // const ShellSubprocessCapturedBufferedWriterMini = bun.shell.SubprocessMini.BufferedOutput.CapturedBufferedWriter;
    // const ShellBufferedOutput = bun.shell.Subprocess.BufferedOutput;
    // const ShellBufferedOutputMini = bun.shell.SubprocessMini.BufferedOutput;
    const Process = bun.spawn.Process;
    const Subprocess = jsc.Subprocess;
    const StaticPipeWriter = Subprocess.StaticPipeWriter.Poll;
    const ShellStaticPipeWriter = bun.shell.ShellSubprocess.StaticPipeWriter.Poll;
    const FileSink = jsc.WebCore.FileSink.Poll;
    const DNSResolver = bun.api.dns.Resolver;
    const GetAddrInfoRequest = bun.api.dns.GetAddrInfoRequest;
    const Request = bun.api.dns.internal.Request;
    const LifecycleScriptSubprocessOutputReader = bun.install.LifecycleScriptSubprocess.OutputReader;
    const BufferedReader = bun.io.BufferedReader;

    pub const Owner = bun.TaggedPointerUnion(.{
        FileSink,

        // ShellBufferedWriter,
        // ShellBufferedWriterMini,
        // ShellBufferedInput,
        // ShellBufferedInputMini,
        // ShellSubprocessCapturedBufferedWriter,
        // ShellSubprocessCapturedBufferedWriterMini,
        // ShellBufferedOutput,
        // ShellBufferedOutputMini,

        StaticPipeWriter,
        ShellStaticPipeWriter,

        // ShellBufferedWriter,

        BufferedReader,

        DNSResolver,
        GetAddrInfoRequest,
        Request,
        // LifecycleScriptSubprocessOutputReader,
        Process,
        ShellBufferedWriter, // i do not know why, but this has to be here otherwise compiler will complain about dependency loop
    });

    pub const AllocatorType = enum {
        js,
        mini,
    };

    fn updateFlags(poll: *FilePoll, updated: Flags.Set) void {
        var flags = poll.flags;
        flags.remove(.readable);
        flags.remove(.writable);
        flags.remove(.process);
        flags.remove(.machport);
        flags.remove(.eof);
        flags.remove(.hup);

        flags.setUnion(updated);
        poll.flags = flags;
    }

    pub fn format(poll: *const FilePoll, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("FilePoll(fd={}, generation_number={d}) = {}", .{ poll.fd, poll.generation_number, Flags.Formatter{ .data = poll.flags } });
    }

    pub fn fileType(poll: *const FilePoll) bun.io.FileType {
        const flags = poll.flags;

        if (flags.contains(.socket)) {
            return .socket;
        }

        if (flags.contains(.nonblocking)) {
            return .nonblocking_pipe;
        }

        return .pipe;
    }

    pub fn onKQueueEvent(poll: *FilePoll, _: *Loop, kqueue_event: *const std.posix.system.kevent64_s) void {
        poll.updateFlags(Flags.fromKQueueEvent(kqueue_event.*));
        log("onKQueueEvent: {}", .{poll});

        if (KQueueGenerationNumber != u0)
            bun.assert(poll.generation_number == kqueue_event.ext[0]);

        poll.onUpdate(kqueue_event.data);
    }

    pub fn onEpollEvent(poll: *FilePoll, _: *Loop, epoll_event: *std.os.linux.epoll_event) void {
        poll.updateFlags(Flags.fromEpollEvent(epoll_event.*));
        poll.onUpdate(0);
    }

    pub fn clearEvent(poll: *FilePoll, flag: Flags) void {
        poll.flags.remove(flag);
    }

    pub fn isReadable(this: *FilePoll) bool {
        const readable = this.flags.contains(.readable);
        this.flags.remove(.readable);
        return readable;
    }

    pub fn isHUP(this: *FilePoll) bool {
        const readable = this.flags.contains(.hup);
        this.flags.remove(.hup);
        return readable;
    }

    pub fn isEOF(this: *FilePoll) bool {
        const readable = this.flags.contains(.eof);
        this.flags.remove(.eof);
        return readable;
    }

    pub fn isWritable(this: *FilePoll) bool {
        const readable = this.flags.contains(.writable);
        this.flags.remove(.writable);
        return readable;
    }

    pub fn deinit(this: *FilePoll) void {
        switch (this.allocator_type) {
            .js => {
                const vm = jsc.VirtualMachine.get();
                const handle = jsc.AbstractVM(vm);
                // const loop = vm.event_loop_handle.?;
                const loop = handle.platformEventLoop();
                const file_polls = handle.filePolls();
                this.deinitPossiblyDefer(vm, loop, file_polls, false);
            },
            .mini => {
                const vm = jsc.MiniEventLoop.global;
                const handle = jsc.AbstractVM(vm);
                // const loop = vm.event_loop_handle.?;
                const loop = handle.platformEventLoop();
                const file_polls = handle.filePolls();
                this.deinitPossiblyDefer(vm, loop, file_polls, false);
            },
        }
    }

    pub fn deinitForceUnregister(this: *FilePoll) void {
        switch (this.allocator_type) {
            .js => {
                var vm = jsc.VirtualMachine.get();
                const loop = vm.event_loop_handle.?;
                this.deinitPossiblyDefer(vm, loop, vm.rareData().filePolls(vm), true);
            },
            .mini => {
                var vm = jsc.MiniEventLoop.global;
                const loop = vm.loop;
                this.deinitPossiblyDefer(vm, loop, vm.filePolls(), true);
            },
        }
    }

    fn deinitPossiblyDefer(this: *FilePoll, vm: anytype, loop: *Loop, polls: *FilePoll.Store, force_unregister: bool) void {
        _ = this.unregister(loop, force_unregister);

        this.owner.clear();
        const was_ever_registered = this.flags.contains(.was_ever_registered);
        this.flags = Flags.Set{};
        this.fd = invalid_fd;
        polls.put(this, vm, was_ever_registered);
    }

    pub fn deinitWithVM(this: *FilePoll, vm_: anytype) void {
        const vm = jsc.AbstractVM(vm_);
        // const loop = vm.event_loop_handle.?;
        const loop = vm.platformEventLoop();
        this.deinitPossiblyDefer(vm_, loop, vm.filePolls(), false);
    }

    pub fn isRegistered(this: *const FilePoll) bool {
        return this.flags.contains(.poll_writable) or this.flags.contains(.poll_readable) or this.flags.contains(.poll_process) or this.flags.contains(.poll_machport);
    }

    const kqueue_or_epoll = if (Environment.isMac) "kevent" else "epoll";

    pub fn onUpdate(poll: *FilePoll, size_or_offset: i64) void {
        if (poll.flags.contains(.one_shot) and !poll.flags.contains(.needs_rearm)) {
            poll.flags.insert(.needs_rearm);
        }

        const ptr = poll.owner;
        bun.assert(!ptr.isNull());

        switch (ptr.tag()) {
            // @field(Owner.Tag, bun.meta.typeBaseName(@typeName(FIFO))) => {
            //     log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) FIFO", .{poll.fd});
            //     ptr.as(FIFO).ready(size_or_offset, poll.flags.contains(.hup));
            // },
            // @field(Owner.Tag, bun.meta.typeBaseName(@typeName(ShellBufferedInput))) => {
            //     log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) ShellBufferedInput", .{poll.fd});
            //     ptr.as(ShellBufferedInput).onPoll(size_or_offset, 0);
            // },

            // @field(Owner.Tag, bun.meta.typeBaseName(@typeName(ShellBufferedWriter))) => {
            //     log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) ShellBufferedWriter", .{poll.fd});
            //     var loader = ptr.as(ShellBufferedWriter);
            //     loader.onPoll(size_or_offset, 0);
            // },
            // @field(Owner.Tag, bun.meta.typeBaseName(@typeName(ShellBufferedWriterMini))) => {
            //     log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) ShellBufferedWriterMini", .{poll.fd});
            //     var loader = ptr.as(ShellBufferedWriterMini);
            //     loader.onPoll(size_or_offset, 0);
            // },
            // @field(Owner.Tag, bun.meta.typeBaseName(@typeName(ShellSubprocessCapturedBufferedWriter))) => {
            //     log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) ShellSubprocessCapturedBufferedWriter", .{poll.fd});
            //     var loader = ptr.as(ShellSubprocessCapturedBufferedWriter);
            //     loader.onPoll(size_or_offset, 0);
            // },
            // @field(Owner.Tag, bun.meta.typeBaseName(@typeName(ShellSubprocessCapturedBufferedWriterMini))) => {
            //     log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) ShellSubprocessCapturedBufferedWriterMini", .{poll.fd});
            //     var loader = ptr.as(ShellSubprocessCapturedBufferedWriterMini);
            //     loader.onPoll(size_or_offset, 0);
            // },
            @field(Owner.Tag, @typeName(ShellBufferedWriter)) => {
                var handler: *ShellBufferedWriter = ptr.as(ShellBufferedWriter);
                handler.onPoll(size_or_offset, poll.flags.contains(.hup));
            },
            @field(Owner.Tag, @typeName(ShellStaticPipeWriter)) => {
                var handler: *ShellStaticPipeWriter = ptr.as(ShellStaticPipeWriter);
                handler.onPoll(size_or_offset, poll.flags.contains(.hup));
            },
            @field(Owner.Tag, @typeName(StaticPipeWriter)) => {
                var handler: *StaticPipeWriter = ptr.as(StaticPipeWriter);
                handler.onPoll(size_or_offset, poll.flags.contains(.hup));
            },
            @field(Owner.Tag, @typeName(FileSink)) => {
                var handler: *FileSink = ptr.as(FileSink);
                handler.onPoll(size_or_offset, poll.flags.contains(.hup));
            },
            @field(Owner.Tag, @typeName(BufferedReader)) => {
                log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) Reader", .{poll.fd});
                var handler: *BufferedReader = ptr.as(BufferedReader);
                handler.onPoll(size_or_offset, poll.flags.contains(.hup));
            },

            @field(Owner.Tag, @typeName(Process)) => {
                log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) Process", .{poll.fd});
                var loader = ptr.as(Process);

                loader.onWaitPidFromEventLoopTask();
            },

            @field(Owner.Tag, @typeName(DNSResolver)) => {
                log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) DNSResolver", .{poll.fd});
                var loader: *DNSResolver = ptr.as(DNSResolver);
                loader.onDNSPoll(poll);
            },

            @field(Owner.Tag, @typeName(GetAddrInfoRequest)) => {
                if (comptime !Environment.isMac) {
                    unreachable;
                }

                log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) GetAddrInfoRequest", .{poll.fd});
                var loader: *GetAddrInfoRequest = ptr.as(GetAddrInfoRequest);
                loader.onMachportChange();
            },

            @field(Owner.Tag, @typeName(Request)) => {
                if (comptime !Environment.isMac) {
                    unreachable;
                }

                log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) InternalDNSRequest", .{poll.fd});
                const loader: *Request = ptr.as(Request);
                Request.MacAsyncDNS.onMachportChange(loader);
            },

            else => {
                const possible_name = Owner.typeNameFromTag(@intFromEnum(ptr.tag()));
                log("onUpdate " ++ kqueue_or_epoll ++ " (fd: {}) disconnected? (maybe: {s})", .{ poll.fd, possible_name orelse "<unknown>" });
            },
        }
    }

    pub const Flags = enum {
        // What are we asking the event loop about?

        /// Poll for readable events
        poll_readable,

        /// Poll for writable events
        poll_writable,

        /// Poll for process-related events
        poll_process,

        /// Poll for machport events
        poll_machport,

        // What did the event loop tell us?
        readable,
        writable,
        process,
        eof,
        hup,
        machport,

        // What is the type of file descriptor?
        fifo,
        tty,

        one_shot,
        needs_rearm,

        has_incremented_poll_count,
        has_incremented_active_count,
        closed,

        keeps_event_loop_alive,

        nonblocking,

        was_ever_registered,
        ignore_updates,

        /// Was O_NONBLOCK set on the file descriptor?
        nonblock,

        socket,

        pub fn poll(this: Flags) Flags {
            return switch (this) {
                .readable => .poll_readable,
                .writable => .poll_writable,
                .process => .poll_process,
                .machport => .poll_machport,
                else => this,
            };
        }

        pub const Set = std.EnumSet(Flags);
        pub const Struct = std.enums.EnumFieldStruct(Flags, bool, false);

        pub const Formatter = std.fmt.Formatter(Flags.format);

        pub fn format(this: Flags.Set, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            var iter = this.iterator();
            var is_first = true;
            while (iter.next()) |flag| {
                if (!is_first) {
                    try writer.print(" | ", .{});
                }
                try writer.writeAll(@tagName(flag));
                is_first = false;
            }
        }

        pub fn fromKQueueEvent(kqueue_event: std.posix.system.kevent64_s) Flags.Set {
            var flags = Flags.Set{};
            if (kqueue_event.filter == std.posix.system.EVFILT.READ) {
                flags.insert(Flags.readable);
                if (kqueue_event.flags & std.posix.system.EV.EOF != 0) {
                    flags.insert(Flags.hup);
                }
            } else if (kqueue_event.filter == std.posix.system.EVFILT.WRITE) {
                flags.insert(Flags.writable);
                if (kqueue_event.flags & std.posix.system.EV.EOF != 0) {
                    flags.insert(Flags.hup);
                }
            } else if (kqueue_event.filter == std.posix.system.EVFILT.PROC) {
                flags.insert(Flags.process);
            } else if (kqueue_event.filter == std.posix.system.EVFILT.MACHPORT) {
                flags.insert(Flags.machport);
            }
            return flags;
        }

        pub fn fromEpollEvent(epoll: std.os.linux.epoll_event) Flags.Set {
            var flags = Flags.Set{};
            if (epoll.events & std.os.linux.EPOLL.IN != 0) {
                flags.insert(Flags.readable);
            }
            if (epoll.events & std.os.linux.EPOLL.OUT != 0) {
                flags.insert(Flags.writable);
            }
            if (epoll.events & std.os.linux.EPOLL.ERR != 0) {
                flags.insert(Flags.eof);
            }
            if (epoll.events & std.os.linux.EPOLL.HUP != 0) {
                flags.insert(Flags.hup);
            }
            return flags;
        }
    };

    const HiveArray = bun.HiveArray(FilePoll, if (bun.heap_breakdown.enabled) 0 else 128).Fallback;

    // We defer freeing FilePoll until the end of the next event loop iteration
    // This ensures that we don't free a FilePoll before the next callback is called
    pub const Store = struct {
        hive: HiveArray,
        pending_free_head: ?*FilePoll = null,
        pending_free_tail: ?*FilePoll = null,

        const log = Output.scoped(.FilePoll, false);

        pub fn init() Store {
            return .{
                .hive = HiveArray.init(bun.typedAllocator(FilePoll)),
            };
        }

        pub fn get(this: *Store) *FilePoll {
            return this.hive.get();
        }

        pub fn processDeferredFrees(this: *Store) void {
            var next = this.pending_free_head;
            while (next) |current| {
                next = current.next_to_free;
                current.next_to_free = null;
                this.hive.put(current);
            }
            this.pending_free_head = null;
            this.pending_free_tail = null;
        }

        pub fn put(this: *Store, poll: *FilePoll, vm: anytype, ever_registered: bool) void {
            if (!ever_registered) {
                this.hive.put(poll);
                return;
            }

            bun.assert(poll.next_to_free == null);

            if (this.pending_free_tail) |tail| {
                bun.assert(this.pending_free_head != null);
                bun.assert(tail.next_to_free == null);
                tail.next_to_free = poll;
            }

            if (this.pending_free_head == null) {
                this.pending_free_head = poll;
                bun.assert(this.pending_free_tail == null);
            }

            poll.flags.insert(.ignore_updates);
            this.pending_free_tail = poll;

            const callback = jsc.OpaqueWrap(Store, processDeferredFrees);
            bun.assert(vm.after_event_loop_callback == null or vm.after_event_loop_callback == @as(?jsc.OpaqueCallback, callback));
            vm.after_event_loop_callback = callback;
            vm.after_event_loop_callback_ctx = this;
        }
    };

    const log = bun.sys.syslog;

    pub inline fn isActive(this: *const FilePoll) bool {
        return this.flags.contains(.has_incremented_poll_count);
    }

    pub inline fn isWatching(this: *const FilePoll) bool {
        return !this.flags.contains(.needs_rearm) and (this.flags.contains(.poll_readable) or this.flags.contains(.poll_writable) or this.flags.contains(.poll_process));
    }

    /// This decrements the active counter if it was previously incremented
    /// "active" controls whether or not the event loop should potentially idle
    pub fn disableKeepingProcessAlive(this: *FilePoll, event_loop_ctx_: anytype) void {
        if (comptime @TypeOf(event_loop_ctx_) == *jsc.EventLoop) {
            disableKeepingProcessAlive(this, jsc.EventLoopHandle.init(event_loop_ctx_));
            return;
        }

        if (comptime @TypeOf(event_loop_ctx_) == jsc.EventLoopHandle) {
            event_loop_ctx_.loop().subActive(@as(u32, @intFromBool(this.flags.contains(.has_incremented_active_count))));
        } else {
            const event_loop_ctx = jsc.AbstractVM(event_loop_ctx_);
            // log("{x} disableKeepingProcessAlive", .{@intFromPtr(this)});
            // vm.event_loop_handle.?.subActive(@as(u32, @intFromBool(this.flags.contains(.has_incremented_active_count))));
            event_loop_ctx.platformEventLoop().subActive(@as(u32, @intFromBool(this.flags.contains(.has_incremented_active_count))));
        }

        this.flags.remove(.keeps_event_loop_alive);
        this.flags.remove(.has_incremented_active_count);
    }

    pub inline fn canEnableKeepingProcessAlive(this: *const FilePoll) bool {
        return this.flags.contains(.keeps_event_loop_alive) and this.flags.contains(.has_incremented_poll_count);
    }

    pub fn setKeepingProcessAlive(this: *FilePoll, event_loop_ctx_: anytype, value: bool) void {
        if (value) {
            this.enableKeepingProcessAlive(event_loop_ctx_);
        } else {
            this.disableKeepingProcessAlive(event_loop_ctx_);
        }
    }
    pub fn enableKeepingProcessAlive(this: *FilePoll, event_loop_ctx_: anytype) void {
        if (comptime @TypeOf(event_loop_ctx_) == *jsc.EventLoop) {
            enableKeepingProcessAlive(this, jsc.EventLoopHandle.init(event_loop_ctx_));
            return;
        }

        if (this.flags.contains(.closed))
            return;

        if (comptime @TypeOf(event_loop_ctx_) == jsc.EventLoopHandle) {
            event_loop_ctx_.loop().addActive(@as(u32, @intFromBool(!this.flags.contains(.has_incremented_active_count))));
        } else {
            const event_loop_ctx = jsc.AbstractVM(event_loop_ctx_);
            event_loop_ctx.platformEventLoop().addActive(@as(u32, @intFromBool(!this.flags.contains(.has_incremented_active_count))));
        }

        this.flags.insert(.keeps_event_loop_alive);
        this.flags.insert(.has_incremented_active_count);
    }

    /// Only intended to be used from EventLoop.Pollable
    fn deactivate(this: *FilePoll, loop: *Loop) void {
        if (this.flags.contains(.has_incremented_poll_count)) loop.dec();
        this.flags.remove(.has_incremented_poll_count);

        loop.subActive(@as(u32, @intFromBool(this.flags.contains(.has_incremented_active_count))));
        this.flags.remove(.keeps_event_loop_alive);
        this.flags.remove(.has_incremented_active_count);
    }

    /// Only intended to be used from EventLoop.Pollable
    fn activate(this: *FilePoll, loop: *Loop) void {
        this.flags.remove(.closed);

        if (!this.flags.contains(.has_incremented_poll_count)) loop.inc();
        this.flags.insert(.has_incremented_poll_count);

        if (this.flags.contains(.keeps_event_loop_alive)) {
            loop.addActive(@as(u32, @intFromBool(!this.flags.contains(.has_incremented_active_count))));
            this.flags.insert(.has_incremented_active_count);
        }
    }

    pub fn init(vm: anytype, fd: bun.FileDescriptor, flags: Flags.Struct, comptime Type: type, owner: *Type) *FilePoll {
        if (comptime @TypeOf(vm) == *bun.install.PackageManager) {
            return init(jsc.EventLoopHandle.init(&vm.event_loop), fd, flags, Type, owner);
        }

        if (comptime @TypeOf(vm) == jsc.EventLoopHandle) {
            var poll = vm.filePolls().get();
            poll.fd = fd;
            poll.flags = Flags.Set.init(flags);
            poll.owner = Owner.init(owner);
            poll.next_to_free = null;
            poll.allocator_type = if (vm == .js) .js else .mini;

            if (KQueueGenerationNumber != u0) {
                max_generation_number +%= 1;
                poll.generation_number = max_generation_number;
            }
            log("FilePoll.init(0x{x}, generation_number={d}, fd={})", .{ @intFromPtr(poll), poll.generation_number, fd });
            return poll;
        }

        return initWithOwner(vm, fd, flags, Owner.init(owner));
    }

    pub fn initWithOwner(vm_: anytype, fd: bun.FileDescriptor, flags: Flags.Struct, owner: Owner) *FilePoll {
        const vm = jsc.AbstractVM(vm_);
        var poll = vm.allocFilePoll();
        poll.fd = fd;
        poll.flags = Flags.Set.init(flags);
        poll.owner = owner;
        poll.next_to_free = null;
        poll.allocator_type = if (comptime @TypeOf(vm_) == *jsc.VirtualMachine) .js else .mini;

        if (KQueueGenerationNumber != u0) {
            max_generation_number +%= 1;
            poll.generation_number = max_generation_number;
        }

        log("FilePoll.initWithOwner(0x{x}, generation_number={d}, fd={})", .{ @intFromPtr(poll), poll.generation_number, fd });
        return poll;
    }

    pub inline fn canRef(this: *const FilePoll) bool {
        if (this.flags.contains(.disable))
            return false;

        return !this.flags.contains(.has_incremented_poll_count);
    }

    pub inline fn canUnref(this: *const FilePoll) bool {
        return this.flags.contains(.has_incremented_poll_count);
    }

    /// Prevent a poll from keeping the process alive.
    pub fn unref(this: *FilePoll, event_loop_ctx_: anytype) void {
        log("unref", .{});
        this.disableKeepingProcessAlive(event_loop_ctx_);
    }

    /// Allow a poll to keep the process alive.
    pub fn ref(this: *FilePoll, event_loop_ctx_: anytype) void {
        if (this.flags.contains(.closed))
            return;

        log("ref", .{});

        this.enableKeepingProcessAlive(event_loop_ctx_);
    }

    pub fn onEnded(this: *FilePoll, event_loop_ctx_: anytype) void {
        const event_loop_ctx = jsc.AbstractVM(event_loop_ctx_);
        this.flags.remove(.keeps_event_loop_alive);
        this.flags.insert(.closed);
        // this.deactivate(vm.event_loop_handle.?);
        this.deactivate(event_loop_ctx.platformEventLoop());
    }

    pub fn onTick(loop: *Loop, tagged_pointer: ?*anyopaque) callconv(.C) void {
        var tag = Pollable.from(tagged_pointer);

        if (tag.tag() != @field(Pollable.Tag, @typeName(FilePoll)))
            return;

        var file_poll: *FilePoll = tag.as(FilePoll);
        if (file_poll.flags.contains(.ignore_updates)) {
            return;
        }

        if (comptime Environment.isMac)
            onKQueueEvent(file_poll, loop, &loop.ready_polls[@as(usize, @intCast(loop.current_ready_poll))])
        else if (comptime Environment.isLinux)
            onEpollEvent(file_poll, loop, &loop.ready_polls[@as(usize, @intCast(loop.current_ready_poll))]);
    }

    const Pollable = bun.TaggedPointerUnion(.{
        FilePoll,
    });

    comptime {
        @export(&onTick, .{ .name = "Bun__internal_dispatch_ready_poll" });
    }

    const timeout = std.mem.zeroes(std.posix.timespec);
    const kevent = std.c.kevent;
    const linux = std.os.linux;

    pub const OneShotFlag = enum { dispatch, one_shot, none };

    pub fn register(this: *FilePoll, loop: *Loop, flag: Flags, one_shot: bool) bun.sys.Maybe(void) {
        return registerWithFd(this, loop, flag, if (one_shot) .one_shot else .none, this.fd);
    }

    pub fn registerWithFd(this: *FilePoll, loop: *Loop, flag: Flags, one_shot: OneShotFlag, fd: bun.FileDescriptor) bun.sys.Maybe(void) {
        const watcher_fd = loop.fd;

        log("register: FilePoll(0x{x}, generation_number={d}) {s} ({})", .{ @intFromPtr(this), this.generation_number, @tagName(flag), fd });

        bun.assert(fd != invalid_fd);

        if (one_shot != .none) {
            this.flags.insert(.one_shot);
        }

        if (comptime Environment.isLinux) {
            const one_shot_flag: u32 = if (!this.flags.contains(.one_shot)) 0 else linux.EPOLL.ONESHOT;

            const flags: u32 = switch (flag) {
                .process,
                .readable,
                => linux.EPOLL.IN | linux.EPOLL.HUP | one_shot_flag,
                .writable => linux.EPOLL.OUT | linux.EPOLL.HUP | linux.EPOLL.ERR | one_shot_flag,
                else => unreachable,
            };

            var event = linux.epoll_event{ .events = flags, .data = .{ .u64 = @intFromPtr(Pollable.init(this).ptr()) } };

            const op: u32 = if (this.isRegistered() or this.flags.contains(.needs_rearm)) linux.EPOLL.CTL_MOD else linux.EPOLL.CTL_ADD;

            const ctl = linux.epoll_ctl(
                watcher_fd,
                op,
                fd.cast(),
                &event,
            );
            this.flags.insert(.was_ever_registered);
            if (bun.sys.Maybe(void).errnoSys(ctl, .epoll_ctl)) |errno| {
                this.deactivate(loop);
                return errno;
            }
        } else if (comptime Environment.isMac) {
            var changelist = std.mem.zeroes([2]std.posix.system.kevent64_s);
            const one_shot_flag: u16 = if (!this.flags.contains(.one_shot))
                0
            else if (one_shot == .dispatch)
                std.c.EV.DISPATCH | std.c.EV.ENABLE
            else
                std.c.EV.ONESHOT;

            changelist[0] = switch (flag) {
                .readable => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.READ,
                    .data = 0,
                    .fflags = 0,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.ADD | one_shot_flag,
                    .ext = .{ this.generation_number, 0 },
                },
                .writable => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.WRITE,
                    .data = 0,
                    .fflags = 0,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.ADD | one_shot_flag,
                    .ext = .{ this.generation_number, 0 },
                },
                .process => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.PROC,
                    .data = 0,
                    .fflags = std.c.NOTE.EXIT,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.ADD | one_shot_flag,
                    .ext = .{ this.generation_number, 0 },
                },
                .machport => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.MACHPORT,
                    .data = 0,
                    .fflags = 0,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.ADD | one_shot_flag,
                    .ext = .{ this.generation_number, 0 },
                },
                else => unreachable,
            };

            // output events only include change errors
            const KEVENT_FLAG_ERROR_EVENTS = 0x000002;

            // The kevent() system call returns the number of events placed in
            // the eventlist, up to the value given by nevents.  If the time
            // limit expires, then kevent() returns 0.
            const rc = rc: {
                while (true) {
                    const rc = std.posix.system.kevent64(
                        watcher_fd,
                        &changelist,
                        1,
                        // The same array may be used for the changelist and eventlist.
                        &changelist,
                        // we set 0 here so that if we get an error on
                        // registration, it becomes errno
                        0,
                        KEVENT_FLAG_ERROR_EVENTS,
                        &timeout,
                    );

                    if (bun.sys.getErrno(rc) == .INTR) continue;
                    break :rc rc;
                }
            };

            this.flags.insert(.was_ever_registered);

            // If an error occurs while
            // processing an element of the changelist and there is enough room
            // in the eventlist, then the event will be placed in the eventlist
            // with EV_ERROR set in flags and the system error in data.
            if (changelist[0].flags == std.c.EV.ERROR and changelist[0].data != 0) {
                return bun.sys.Maybe(void).errnoSys(changelist[0].data, .kevent).?;
                // Otherwise, -1 will be returned, and errno will be set to
                // indicate the error condition.
            }

            const errno = bun.sys.getErrno(rc);

            if (errno != .SUCCESS) {
                this.deactivate(loop);
                return .initErr(bun.sys.Error.fromCode(errno, .kqueue));
            }
        } else {
            @compileError("unsupported platform");
        }
        this.activate(loop);
        this.flags.insert(switch (flag) {
            .readable => .poll_readable,
            .process => if (comptime Environment.isLinux) .poll_readable else .poll_process,
            .writable => .poll_writable,
            .machport => .poll_machport,
            else => unreachable,
        });
        this.flags.remove(.needs_rearm);

        return .success;
    }

    const invalid_fd = bun.invalid_fd;

    pub inline fn fileDescriptor(this: *FilePoll) bun.FileDescriptor {
        return @intCast(this.fd);
    }

    pub fn unregister(this: *FilePoll, loop: *Loop, force_unregister: bool) bun.sys.Maybe(void) {
        return this.unregisterWithFd(loop, this.fd, force_unregister);
    }

    pub fn unregisterWithFd(this: *FilePoll, loop: *Loop, fd: bun.FileDescriptor, force_unregister: bool) bun.sys.Maybe(void) {
        if (Environment.allow_assert) {
            bun.assert(fd.native() >= 0 and fd != bun.invalid_fd);
        }
        defer this.deactivate(loop);

        if (!(this.flags.contains(.poll_readable) or this.flags.contains(.poll_writable) or this.flags.contains(.poll_process) or this.flags.contains(.poll_machport))) {

            // no-op
            return .success;
        }

        bun.assert(fd != invalid_fd);
        const watcher_fd = loop.fd;
        const flag: Flags = brk: {
            if (this.flags.contains(.poll_readable))
                break :brk .readable;
            if (this.flags.contains(.poll_writable))
                break :brk .writable;
            if (this.flags.contains(.poll_process))
                break :brk .process;

            if (this.flags.contains(.poll_machport))
                break :brk .machport;
            return .success;
        };

        if (this.flags.contains(.needs_rearm) and !force_unregister) {
            log("unregister: {s} ({}) skipped due to needs_rearm", .{ @tagName(flag), fd });
            this.flags.remove(.poll_process);
            this.flags.remove(.poll_readable);
            this.flags.remove(.poll_process);
            this.flags.remove(.poll_machport);
            return .success;
        }

        log("unregister: FilePoll(0x{x}, generation_number={d}) {s} ({})", .{ @intFromPtr(this), this.generation_number, @tagName(flag), fd });

        if (comptime Environment.isLinux) {
            const ctl = linux.epoll_ctl(
                watcher_fd,
                linux.EPOLL.CTL_DEL,
                fd.cast(),
                null,
            );

            if (bun.sys.Maybe(void).errnoSys(ctl, .epoll_ctl)) |errno| {
                return errno;
            }
        } else if (comptime Environment.isMac) {
            var changelist = std.mem.zeroes([2]std.posix.system.kevent64_s);

            changelist[0] = switch (flag) {
                .readable => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.READ,
                    .data = 0,
                    .fflags = 0,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.DELETE,
                    .ext = .{ 0, 0 },
                },
                .machport => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.MACHPORT,
                    .data = 0,
                    .fflags = 0,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.DELETE,
                    .ext = .{ 0, 0 },
                },
                .writable => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.WRITE,
                    .data = 0,
                    .fflags = 0,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.DELETE,
                    .ext = .{ 0, 0 },
                },
                .process => .{
                    .ident = @intCast(fd.cast()),
                    .filter = std.posix.system.EVFILT.PROC,
                    .data = 0,
                    .fflags = std.c.NOTE.EXIT,
                    .udata = @intFromPtr(Pollable.init(this).ptr()),
                    .flags = std.c.EV.DELETE,
                    .ext = .{ 0, 0 },
                },
                else => unreachable,
            };

            // output events only include change errors
            const KEVENT_FLAG_ERROR_EVENTS = 0x000002;

            // The kevent() system call returns the number of events placed in
            // the eventlist, up to the value given by nevents.  If the time
            // limit expires, then kevent() returns 0.
            const rc = std.posix.system.kevent64(
                watcher_fd,
                &changelist,
                1,
                // The same array may be used for the changelist and eventlist.
                &changelist,
                1,
                KEVENT_FLAG_ERROR_EVENTS,
                &timeout,
            );
            // If an error occurs while
            // processing an element of the changelist and there is enough room
            // in the eventlist, then the event will be placed in the eventlist
            // with EV_ERROR set in flags and the system error in data.
            if (changelist[0].flags == std.c.EV.ERROR) {
                return bun.sys.Maybe(void).errnoSys(changelist[0].data, .kevent).?;
                // Otherwise, -1 will be returned, and errno will be set to
                // indicate the error condition.
            }

            const errno = bun.sys.getErrno(rc);
            switch (rc) {
                std.math.minInt(@TypeOf(rc))...-1 => return bun.sys.Maybe(void).errnoSys(@intFromEnum(errno), .kevent).?,
                else => {},
            }
        } else {
            @compileError("unsupported platform");
        }

        this.flags.remove(.needs_rearm);
        this.flags.remove(.one_shot);
        // we don't support both right now
        bun.assert(!(this.flags.contains(.poll_readable) and this.flags.contains(.poll_writable)));
        this.flags.remove(.poll_readable);
        this.flags.remove(.poll_writable);
        this.flags.remove(.poll_process);
        this.flags.remove(.poll_machport);

        return .success;
    }
};

pub const Waker = switch (Environment.os) {
    .mac => KEventWaker,
    .linux => LinuxWaker,
    else => @compileError(unreachable),
};

pub const LinuxWaker = struct {
    fd: bun.FileDescriptor,

    pub fn init() !Waker {
        return initWithFileDescriptor(.fromNative(try std.posix.eventfd(0, 0)));
    }

    pub fn getFd(this: *const Waker) bun.FileDescriptor {
        return this.fd;
    }

    pub fn initWithFileDescriptor(fd: bun.FileDescriptor) Waker {
        return Waker{ .fd = fd };
    }

    pub fn wait(this: Waker) void {
        var bytes: usize = 0;
        _ = std.posix.read(this.fd.cast(), @as(*[8]u8, @ptrCast(&bytes))) catch 0;
    }

    pub fn wake(this: *const Waker) void {
        var bytes: usize = 1;
        _ = std.posix.write(
            this.fd.cast(),
            @as(*[8]u8, @ptrCast(&bytes)),
        ) catch 0;
    }
};

pub const KEventWaker = struct {
    kq: std.posix.fd_t,
    machport: bun.mach_port = undefined,
    machport_buf: []u8 = &.{},
    has_pending_wake: bool = false,

    const zeroed = std.mem.zeroes([16]Kevent64);

    const Kevent64 = std.posix.system.kevent64_s;

    pub fn wake(this: *Waker) void {
        bun.jsc.markBinding(@src());

        if (io_darwin_schedule_wakeup(this.machport)) {
            this.has_pending_wake = false;
            return;
        }
        this.has_pending_wake = true;
    }

    pub fn getFd(this: *const Waker) bun.FileDescriptor {
        return .fromNative(this.kq);
    }

    pub fn wait(this: Waker) void {
        if (!bun.FD.fromNative(this.kq).isValid()) {
            return;
        }

        bun.jsc.markBinding(@src());
        var events = zeroed;

        _ = std.posix.system.kevent64(
            this.kq,
            &events,
            0,
            &events,
            events.len,
            0,
            null,
        );
    }

    extern fn io_darwin_close_machport(bun.mach_port) void;

    extern fn io_darwin_create_machport(
        std.posix.fd_t,
        *anyopaque,
        usize,
    ) bun.mach_port;

    extern fn io_darwin_schedule_wakeup(bun.mach_port) bool;

    pub fn init() !Waker {
        return initWithFileDescriptor(bun.default_allocator, try std.posix.kqueue());
    }

    pub fn initWithFileDescriptor(allocator: std.mem.Allocator, kq: i32) !Waker {
        bun.jsc.markBinding(@src());
        bun.assert(kq > -1);
        const machport_buf = try allocator.alloc(u8, 1024);
        const machport = io_darwin_create_machport(
            kq,
            machport_buf.ptr,
            1024,
        );
        if (machport == 0) {
            return error.MachportCreationFailed;
        }

        return Waker{
            .kq = kq,
            .machport = machport,
            .machport_buf = machport_buf,
        };
    }
};

pub const Closer = struct {
    fd: bun.FileDescriptor,
    task: jsc.WorkPoolTask = .{ .callback = &onClose },

    pub const new = bun.TrivialNew(@This());

    pub fn close(
        fd: bun.FileDescriptor,
        /// for compatibility with windows version
        _: void,
    ) void {
        bun.assert(fd.isValid());
        jsc.WorkPool.schedule(&Closer.new(.{ .fd = fd }).task);
    }

    fn onClose(task: *jsc.WorkPoolTask) void {
        const closer: *Closer = @fieldParentPtr("task", task);
        defer bun.destroy(closer);
        closer.fd.close();
    }
};

const std = @import("std");

const bun = @import("bun");
const Environment = bun.Environment;
const Output = bun.Output;
const jsc = bun.jsc;
const uws = bun.uws;
