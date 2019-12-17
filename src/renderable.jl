abstract type Renderable end

"""
Return true if an object or type is *directly renderable*, false otherwise.

New types should implement the `isrenderable(t::Type{NewType})` method.
"""
function isrenderable end

isrenderable(object) = isrenderable(typeof(object))
isrenderable(::Type{R}) where R <: Renderable = true
isrenderable(t::Type) = hasmethod(add_renderable!, Tuple{RenderModel, t})

isrenderable(t::Type{Roadway}) = true


"""
    write_to_svg(surface::CairoSurface, filename::AbstractString)

Write a cairo svg surface to a file. The surface object is destroyed after.
"""
function write_to_svg(surface::CairoSurface, filename::AbstractString)
    finish(surface)
    seek(surface.stream, 0)
    open(filename, "w") do io
        write(io, read(surface.stream, String))
    end
    return 
end


"""
A basic drawable rectangle representing a car.
An arrow indicates the heading direction of the car.

    ArrowCar{A<:AbstractArray{Float64}, C<:Colorant} <: Renderable
    ArrowCar(pos::AbstractArray, angle::Float64=0.0; length = 4.8, width = 1.8,  color=_colortheme["COLOR_CAR_OTHER"], text="", id=0)
    ArrowCar(x::Real, y::Real, angle::Float64=0.0; length = 4.8, width = 1.8,  color=_colortheme["COLOR_CAR_OTHER"], text="", id=0)
"""
@with_kw struct ArrowCar{A<:AbstractArray{Float64}, C<:Colorant} <: Renderable
    pos::A         = SVector(0.0, 0.0)
    angle::Float64 = 0.0
    length::Float64 = 4.8
    width::Float64 = 1.8
    color::C       = _colortheme["COLOR_CAR_OTHER"]
    text::String   = "" # some debugging text to print by the car
    id::Int        = 0
end
ArrowCar(pos::AbstractArray, angle::Float64=0.0; length = 4.8, width = 1.8,  color=_colortheme["COLOR_CAR_OTHER"], text="", id=0) = ArrowCar(pos, angle, length, width, color, text, id)
ArrowCar(x::Real, y::Real, angle::Float64=0.0; length = 4.8, width = 1.8,  color=_colortheme["COLOR_CAR_OTHER"], text="", id=0) = ArrowCar(SVector(x, y), angle, length, width, color, text, id)

function add_renderable!(rm::RenderModel, c::ArrowCar)
    x = c.pos[1]
    y = c.pos[2]
    add_instruction!(rm, render_vehicle, (x, y, c.angle, c.length, c.width, c.color))
    add_instruction!(rm, render_text, (c.text, x, y-c.width/2 - 2.0, 10, colorant"white"))
    return rm
end


"""
A drawable rectangle with rounded corners representing an `entity`.
"""
@with_kw struct EntityRectangle{S,D,I, C<:Colorant} <: Renderable
    entity::Entity{S,D,I}
    color::C = AutoViz._colortheme["COLOR_CAR_OTHER"]
end

function render_entity_rectangle(ctx::CairoContext, er::EntityRectangle)
    x, y, yaw = posg(er.entity.state)
    w, h = length(er.entity.def), AutomotiveDrivingModels.width(er.entity.def)
    cr = 0.5 # [m]
    save(ctx); translate(ctx, x, y); rotate(ctx, yaw);
    color_fill = er.color
    color_line = weighted_color_mean(.4, colorant"black", color_fill)
    render_round_rect(ctx, 0, 0, w, h, 1., cr, color_fill, true, true, color_line, .3)
    restore(ctx)
end
add_renderable!(rm::RenderModel, er::EntityRectangle) = add_instruction!(rm, render_entity_rectangle, (er,))


"""
A drawable arrow representing the current velocity vector of an `entity`.
The arrow points to the location where the vehicle will be one second in the future (assuming linear motion).
"""
@with_kw struct VelocityArrow{S,D,I, C<:Colorant} <: Renderable
    entity::Entity{S,D,I}
    color::C = colorant"white"
end

function render_velocity_arrow(ctx::CairoContext, va::VelocityArrow)
    x, y, yaw = posg(va.entity.state)
    vx, vy = velg(va.entity.state)
    save(ctx); translate(ctx, x, y); rotate(ctx, yaw);
    render_arrow(ctx, [[0.  vx];[0. vy]], va.color, .3, .8, ARROW_WIDTH_RATIO=1., ARROW_ALPHA=.12pi, ARROW_BETA=.6pi)
    restore(ctx)
end
add_renderable!(rm::RenderModel, va::VelocityArrow) = add_instruction!(rm, render_velocity_arrow, (va,))


"""
A drawable 'fancy' svg image of a race car.
The car is placed at the position of `entity` and the width and length are scaled accordingly.
The color of the car can be specified using the `color` keyword.
"""
@with_kw struct FancyCar{C<:Colorant, S, D, I} <: Renderable
    car::Entity{S, D, I}
    color::C = AutoViz._colortheme["COLOR_CAR_OTHER"]
end

function add_renderable!(rm::RenderModel, fc::FancyCar)
    x, y, yaw = posg(fc.car.state)
    l, w = length(fc.car.def), AutomotiveDrivingModels.width(fc.car.def)
    add_instruction!(rm, render_fancy_car, (x, y, yaw, l, w, fc.color))
    return rm
end


"""
A drawable 'fancy' svg image of a pedestrian.
The pedestrian is placed at the position of `entity` and the width and length of the original image are scaled accordingly.
The color of the pedestrian can be specified using the `color` keyword.
"""
@with_kw struct FancyPedestrian{C<:Colorant, S, D, I} <: Renderable
    ped::Entity{S, D, I}
    color::C = colorant"blue"
end

function add_renderable!(rm::RenderModel, fp::FancyPedestrian)
    x, y, yaw = posg(fp.ped.state)
    l, w = length(fp.ped.def), AutomotiveDrivingModels.width(fp.ped.def)
    add_instruction!(rm, render_fancy_pedestrian, (x, y, yaw, l, w, fp.color))
    return rm
end


"""
Helper function for directly rendering entities, takes care of wrapping them in renderable objects
"""
function add_renderable!(
    rendermodel::RenderModel,
    entity::Entity{VehicleState,D,I},
    color::Colorant=RGB(rand(), rand(), rand())
) where {D<:AbstractAgentDefinition, I}
    if _rendermode == :fancy
        fe = (class(entity.def) == AgentClass.PEDESTRIAN ? FancyPedestrian(ped=entity, color=color) : FancyCar(car=entity, color=color))
        add_renderable!(rendermodel, fe)
    else
        er = EntityRectangle(entity=entity, color=color)
        add_renderable!(rendermodel, er)
        va = VelocityArrow(entity=entity, color=color)
        add_renderable!(rendermodel, va)
    end
    return rendermodel
end


"""
Convenience function for rendering a scene. Takes care of initializing a `RenderModel` and updating the camera.
For full control, use `render!(rendermodel, renderables)` instead.
"""
function render(
    # TODO: what about the roadway?
    #  A) only allow rendering with roadway (as a first or second argument), scene without a roadway is not needed
    #  B) implement a second, separate method?
    #  C) allow roadway to be Union{Nothing, Roadway}?
    #  D) more options??
    scene::Frame{E}, overlays=[];
    camera_zoom::Float64 = 10.,
    camera_center::VecE2 = VecE2(0., 0.),
    camera_rotation::Float64 = 0.,
    camera_motion::Camera = SceneFollowCamera(),
    canvas_width::Int=DEFAULT_CANVAS_WIDTH,
    canvas_height::Int=DEFAULT_CANVAS_HEIGHT,
    surface::CairoSurface = CairoSVGSurface(IOBuffer(), canvas_width, canvas_height)
) where {E<:Entity}
    rendermodel = RenderModel(
        camera_center=camera_center, camera_zoom=camera_zoom, camera_rotation=camera_rotation
    )
    update_camera!(rendermodel, camera_motion, scene)

    scene_renderables = []
    for entity in scene
        color = RGB(rand(), rand(), rand())  # TODO: random colors?? if not, how to determine id? 
        if _rendermode == :fancy
            if class(entity.def) == AgentClass.PEDESTRIAN
                push!(scene_renderables, FancyPedestrian(ped=entity, color=color))
            else
                push!(scene_renderables, FancyCar(car=entity, color=color))
            end
        else
            push!(scene_renderables, EntityRectangle(entity=entity, color=color))
            push!(scene_renderables, VelocityArrow(entity=entity, color=color))
        end
    end

    # TODO: roadway or not?
    # [roadway], 
    render!(rendermodel, vcat(scene_renderables, overlays), surface=surface)
    return surface
end
