const std = @import("std");
const sdl = @import("cImport.zig");

// parameters
const refreshrate = 20; // [ms]
const difffactor = 245; // [score on 255]
const sensordist = 10.0; // [pixels]
const sensorangle = 45.0; // [deg]
const moldcount = 30000;

// Start modes (cyclic enum)
const StartMode = enum {
    random,
    dot,
    circle,
    pub fn next(actual: StartMode) StartMode {
        const n = (@as(usize, @intFromEnum(actual)) + 1) % @typeInfo(StartMode).Enum.fields.len;
        return @enumFromInt(n);
    }
};

// Calculated parameters
const sensorrad: comptime_float = sensorangle * std.math.rad_per_deg;
var prng: std.Random.DefaultPrng = undefined;
var molds: [moldcount]Mold = undefined;
var canvas: *sdl.SDL_Surface = undefined;
var width: u32 = undefined;
var height: u32 = undefined;
var wFloat: f32 = undefined;
var hFloat: f32 = undefined;
var pixels: [*]u32 = undefined;
var nextMode = StartMode.random;

// Starting coordinates and heading
fn StartPosition(mode: StartMode, x: *f32, y: *f32, heading: *f32) void {
    const h: f32 = prng.random().float(f32) * std.math.tau;
    const rand: f32 = prng.random().float(f32);
    switch (mode) {
        StartMode.random => {
            x.* = prng.random().float(f32) * wFloat;
            y.* = prng.random().float(f32) * hFloat;
            heading.* = h;
        },
        StartMode.dot => {
            x.* = wFloat / 2.0 + 10.0 * prng.random().float(f32) - 5.0;
            y.* = hFloat / 2.0 + 10.0 * prng.random().float(f32) - 5.0;
            heading.* = h;
        },
        StartMode.circle => {
            x.* = wFloat / 2 - (200.0 + 10.0 * rand) * @cos(h);
            y.* = hFloat / 2 - (200.0 + 10.0 * rand) * @sin(h);
            heading.* = h;
        },
    }
}

// Molds
const Mold = struct {
    x: f32,
    y: f32,
    heading: f32,
    vx: f32,
    vy: f32,
    pub fn init(mode: StartMode) Mold {
        var xp: f32 = undefined;
        var yp: f32 = undefined;
        var h: f32 = undefined;
        StartPosition(mode, &xp, &yp, &h);
        return .{
            .x = xp,
            .y = yp,
            .heading = h,
            .vx = @cos(h),
            .vy = @sin(h),
        };
    }
    pub fn posindex(self: Mold) u32 {
        const x: u32 = @as(u32, @intFromFloat(self.x));
        const y: u32 = @as(u32, @intFromFloat(self.y));
        return x + width * y;
    }
    fn getsensor(self: Mold, angle: f32) u8 {
        const a = self.heading + angle;
        const sensX: u32 = @as(u32, @intFromFloat(@mod(self.x + sensordist * @cos(a) + wFloat, wFloat)));
        const sensY: u32 = @as(u32, @intFromFloat(@mod(self.y + sensordist * @sin(a) + hFloat, hFloat)));
        return @intCast(pixels[width * sensY + sensX] & 0xff);
    }
    pub fn update(self: *Mold) void {
        self.*.x = @mod(self.x + self.vx + wFloat, wFloat);
        self.*.y = @mod(self.y + self.vy + hFloat, hFloat);
        const sensF: u8 = self.getsensor(0.0);
        const sensL: u8 = self.getsensor(-sensorrad);
        const sensR: u8 = self.getsensor(sensorrad);
        if (sensF >= sensL and sensF >= sensR) return;
        if (sensF < sensL and sensF < sensR) {
            if (prng.random().boolean()) {
                self.heading += sensorrad;
            } else self.heading -= sensorrad;
        } else if (sensL > sensR) {
            self.heading -= sensorrad;
        } else self.heading += sensorrad;
        self.vx = @cos(self.heading);
        self.vy = @sin(self.heading);
    }
};

fn RestartPopulation() void {
    _ = sdl.SDL_FillRect(canvas, null, sdl.SDL_MapRGB(canvas.format, 0, 0, 0));
    for (&molds) |*mold| mold.* = Mold.init(nextMode);
    nextMode = StartMode.next(nextMode);
}

pub fn main() !void {
    // initialise Randomizer
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    prng = std.Random.DefaultPrng.init(seed);
    // initialise SDL
    if (sdl.SDL_Init(sdl.SDL_INIT_TIMER | sdl.SDL_INIT_VIDEO) != 0) {
        std.debug.print("SDL initialisation error: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_initialisationerror;
    }
    defer sdl.SDL_Quit();
    // Prepare full screen (stable alternative for linux)
    var dm: sdl.SDL_DisplayMode = undefined;
    if (sdl.SDL_GetDisplayMode(0, 0, &dm) != 0) {
        std.debug.print("SDL GetDisplayMode error: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_initialisationerror;
    }
    const window: *sdl.SDL_Window = sdl.SDL_CreateWindow(
        "Game window",
        0,
        0,
        dm.w,
        dm.h,
        sdl.SDL_WINDOW_BORDERLESS | sdl.SDL_WINDOW_MAXIMIZED,
    ) orelse {
        std.debug.print("SDL window creation failed: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_initialisationerror;
    };
    defer sdl.SDL_DestroyWindow(window);
    canvas = sdl.SDL_GetWindowSurface(window) orelse {
        std.debug.print("SDL window surface creation failed: {s}\n", .{sdl.SDL_GetError()});
        return error.sld_surfacecreationfailed;
    };
    width = @intCast(canvas.w);
    height = @intCast(canvas.h);
    wFloat = @floatFromInt(width);
    hFloat = @floatFromInt(height);
    pixels = @as([*]u32, @ptrCast(@alignCast(canvas.*.pixels)));
    const dotcolor = sdl.SDL_MapRGB(canvas.format, 255, 255, 255);
    std.debug.print("Window dimensions: {}x{}\n", .{ width, height });
    _ = sdl.SDL_FillRect(canvas, null, 0);
    // Create diffusing background
    const diffback = sdl.SDL_CreateRGBSurfaceWithFormat(
        0,
        canvas.w,
        canvas.h,
        canvas.format.*.BytesPerPixel,
        canvas.format.*.format,
    );
    const diffcolor = sdl.SDL_MapRGBA(diffback.*.format, difffactor, difffactor, difffactor, 255);
    _ = sdl.SDL_FillRect(diffback, null, diffcolor);
    _ = sdl.SDL_SetSurfaceBlendMode(diffback, sdl.SDL_BLENDMODE_MOD);

    // Tweak background openGL to avoid screen flickering
    if (sdl.SDL_GL_GetCurrentContext() != null) {
        _ = sdl.SDL_GL_SetSwapInterval(1);
        std.debug.print("Adapted current openGL context for vSync\n", .{});
    }

    // Hide mouse
    _ = sdl.SDL_ShowCursor(sdl.SDL_DISABLE);

    // Initialise Mold Population
    RestartPopulation();

    // Initialise loop
    var timer = try std.time.Timer.start();
    var stoploop = false;
    var event: sdl.SDL_Event = undefined;

    // Do the loop!
    while (!stoploop) {
        timer.reset();
        _ = sdl.SDL_UpdateWindowSurface(window);
        _ = sdl.SDL_BlitSurface(diffback, null, canvas, null);
        for (&molds) |*mold| {
            pixels[mold.posindex()] = dotcolor;
            mold.update();
        }
        while (sdl.SDL_PollEvent(&event) != 0) {
            if (event.type == sdl.SDL_KEYDOWN) {
                if (event.key.keysym.sym == sdl.SDLK_SPACE) {
                    RestartPopulation();
                } else stoploop = true;
            }
        }
        const lap: u32 = @intCast(timer.read() / 1_000_000);
        if (lap < refreshrate) sdl.SDL_Delay(refreshrate - lap);
    }
}
