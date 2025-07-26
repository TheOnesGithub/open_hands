pub const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Rotation = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Scale = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Transform = struct {
    position: Position,
    rotation: Rotation,
    scale: Scale,
};
