const std = @import("std");
const sdl = @cImport(@cInclude("C:\\Users\\Public\\Includes\\SDL2\\include\\SDL.h"));

// parameters
const refreshrate = 20; // [ms]
const difffactor = 245; // [score on 255]
const sensordist = 10.0; // [pixels]
const sensorangle = 45.0;
const moldcount = 30000;

// Calculated parameters
const sensorrad: comptime_float = sensorangle * std.math.rad_per_deg;
var prng: std.Random.DefaultPrng = undefined;
var height: u32 = undefined;
var width: u32 = undefined;
var pixels: [*]u32 = undefined;

// Molds
const Mold = struct {
    x: f32,
    y: f32,
    heading: f32,
    vx: f32,
    vy: f32,
    wf: f32,
    hf: f32,
    pub fn init() Mold {
        const heading: f32 = prng.random().float(f32) * 2.0 * std.math.pi;
        const wf = @as(f32, @floatFromInt(width));
        const hf = @as(f32, @floatFromInt(height));
        return .{
            .x = prng.random().float(f32) * wf,
            .y = prng.random().float(f32) * hf,
            .heading = heading,
            .vx = @cos(heading),
            .vy = @sin(heading),
            .wf = wf,
            .hf = hf,
        };
    }
    pub fn posindex(self: Mold) u32 {
        const x: u32 = @as(u32, @intFromFloat(self.x));
        const y: u32 = @as(u32, @intFromFloat(self.y));
        return x + width * y;
    }
    fn getsensor(self: Mold, angle: f32) u8 {
        const a = self.heading + angle;
        const sensX: u32 = @as(u32, @intFromFloat(@mod(self.x + sensordist * @cos(a) + self.wf, self.wf)));
        const sensY: u32 = @as(u32, @intFromFloat(@mod(self.y + sensordist * @sin(a) + self.hf, self.hf)));
        return @intCast(pixels[width * sensY + sensX] & 0xff);
    }
    pub fn update(self: *Mold) void {
        self.*.x = @mod(self.x + self.vx + self.wf, self.wf);
        self.*.y = @mod(self.y + self.vy + self.hf, self.hf);
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

pub fn main() !void {
    // initialise Randomizer
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    prng = std.Random.DefaultPrng.init(seed);
    // initialise SDL
    if (sdl.SDL_Init(sdl.SDL_INIT_TIMER) != 0) {
        std.debug.print("SDL initialisation error: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_initialisationerror;
    }
    defer sdl.SDL_Quit();
    const window: *sdl.SDL_Window = sdl.SDL_CreateWindow("Game window", 0, 0, 1600, 900, sdl.SDL_WINDOW_FULLSCREEN_DESKTOP) orelse {
        std.debug.print("SDL window creation failed: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_windowcreationfailed;
    };
    defer sdl.SDL_DestroyWindow(window);
    const canvas: *sdl.SDL_Surface = sdl.SDL_GetWindowSurface(window) orelse {
        std.debug.print("SDL window surface creation failed: {s}\n", .{sdl.SDL_GetError()});
        return error.sld_surfacecreationfailed;
    };
    width = @intCast(canvas.w);
    height = @intCast(canvas.h);
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

    // Hide mouse
    _ = sdl.SDL_ShowCursor(sdl.SDL_DISABLE);

    // Initialise Mold Population
    var molds: [moldcount]Mold = undefined;
    for (&molds) |*mold| mold.* = Mold.init();

    var timer = try std.time.Timer.start();
    var stoploop = false;
    var event: sdl.SDL_Event = undefined;
    while (!stoploop) {
        timer.reset();
        _ = sdl.SDL_UpdateWindowSurface(window);
        _ = sdl.SDL_BlitSurface(diffback, null, canvas, null);
        for (&molds) |*mold| {
            pixels[mold.posindex()] = dotcolor;
            mold.update();
        }
        while (sdl.SDL_PollEvent(&event) != 0) {
            if (event.type == sdl.SDL_KEYDOWN) stoploop = true;
        }
        const lap: u32 = @intCast(timer.read() / 1_000_000);
        if (lap < refreshrate) sdl.SDL_Delay(refreshrate - lap);
    }
}
