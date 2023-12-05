extends Area3D
class_name GrassField

@export var shape: Shape3D
@export var count_x: int = 128
@export var count_z: int = 128

@export var rain_size : float = 3.0
@export var mouse_size : float = 5.0
@export var texture_size : Vector2i = Vector2i(512, 512)
@export_range(1.0, 10.0, 0.1) var damp : float = 1.0

var t = 0.0
var max_t = 0.1

var texture : Texture2DRD
var next_texture : int = 0

@onready var instance := $MultiMeshInstance3D

var target_collider: CollisionObject3D
var target_position: Vector3
var target_radius := 0.1


func _ready():
	_initialize_mesh()
	
	RenderingServer.call_on_render_thread(_initialize_compute_code.bind(texture_size))

	texture = Texture2DRD.new()
	var material : ShaderMaterial = instance.material_override
	if material:
		material.set_shader_parameter("effect_texture_size", texture_size)
		material.set_shader_parameter("effect_texture", texture)
		
		var noise_texture = NoiseTexture2D.new()
		noise_texture.noise = FastNoiseLite.new()
		material.set_shader_parameter("noise_texture", noise_texture)
	
	body_entered.connect(_body_entered)
	body_exited.connect(_body_exited)


func _exit_tree():
	# Make sure we clean up!
	if texture:
		texture.texture_rd_rid = RID()

	RenderingServer.call_on_render_thread(_free_compute_resources)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# Increase our next texture index.
	next_texture = (next_texture + 1) % 3

	if texture:
		texture.texture_rd_rid = texture_rds[next_texture]

	if target_collider:
		target_position = (target_collider.global_position - global_position) * 0.2

	RenderingServer.call_on_render_thread(_render_process.bind(next_texture, delta))


func _body_entered(body: Node3D) -> void:
	if body is CollisionObject3D:
		target_collider = body


func _body_exited(body: Node3D) -> void:
	if target_collider == body:
		target_collider = null


###############################################################################
# Everything after this point is designed to run on our rendering thread.

var rd : RenderingDevice

var shader : RID
var pipeline : RID

# We use 3 textures:
# - One to render into
# - One that contains the last frame rendered
# - One for the frame before that
var texture_rds : Array = [ RID(), RID(), RID() ]
var texture_sets : Array = [ RID(), RID(), RID() ]

func _create_uniform_image(texture_rd : RID) -> RID:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rd)
	return rd.uniform_set_create([uniform], shader, 0)


func _initialize_compute_code(init_with_texture_size):
	# As this becomes part of our normal frame rendering,
	# we use our main rendering device here.
	rd = RenderingServer.get_rendering_device()

	# Create our shader.
	var shader_file = load("res://grass_field/grass_field.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)

	# Create our textures to manage our wave.
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = init_with_texture_size.x
	tf.height = init_with_texture_size.y
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT

	for i in range(3):
		# Create our texture.
		texture_rds[i] = rd.texture_create(tf, RDTextureView.new(), [])

		# Make sure our textures are cleared.
		rd.texture_clear(texture_rds[i], Color(0, 0, 0, 0), 0, 1, 0, 1)

		# Now create our uniform set so we can use these textures in our shader.
		texture_sets[i] = _create_uniform_image(texture_rds[i])
	

func _render_process(with_next_texture: int, delta: float):
	# We don't have structures (yet) so we need to build our push constant
	# "the hard way"...
	var push_constant : PackedFloat32Array = PackedFloat32Array()
	push_constant.push_back(target_position.x)
	push_constant.push_back(target_position.y)
	push_constant.push_back(target_position.z)
	push_constant.push_back(target_radius)

	push_constant.push_back(texture_size.x)
	push_constant.push_back(texture_size.y)
	push_constant.push_back(damp)
	push_constant.push_back(delta)

	# Calculate our dispatch group size.
	# We do `n - 1 / 8 + 1` in case our texture size is not nicely
	# divisible by 8.
	# In combination with a discard check in the shader this ensures
	# we cover the entire texture.
	var x_groups = ((texture_size.x - 1) >> 3) + 1
	var y_groups = ((texture_size.y - 1) >> 3) + 1

	var next_set = texture_sets[with_next_texture]
	var current_set = texture_sets[(with_next_texture - 1) % 3]
	var previous_set = texture_sets[(with_next_texture - 2) % 3]

	# Run our compute shader.
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, current_set, 0)
	rd.compute_list_bind_uniform_set(compute_list, previous_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, next_set, 2)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

	# We don't need to sync up here, Godots default barriers will do the trick.
	# If you want the output of a compute shader to be used as input of
	# another computer shader you'll need to add a barrier:
	#rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)


func _free_compute_resources():
	# Note that our sets and pipeline are cleaned up automatically as they are dependencies :P
	for i in range(3):
		if texture_rds[i]:
			rd.free_rid(texture_rds[i])

	if shader:
		rd.free_rid(shader)


func _initialize_mesh() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(3):
		var t1 := i * PI * 2 / 3
		var t2 := (i + 1) * PI * 2 / 3
		var v0 := Vector3(0.0, 1.0, 0.0)
		var v1 := Vector3(cos(t1), 0.0, sin(t1)) * 0.04
		var v2 := Vector3(cos(t2), 0.0, sin(t2)) * 0.04
		st.set_normal((v2 - v0).normalized().cross((v1 - v0).normalized()))
		st.add_vertex(v0)
		st.add_vertex(v1)
		st.add_vertex(v2)

	instance.multimesh.mesh = st.commit()

	var box_shape: BoxShape3D = shape
	var area_size := box_shape.size
	var area_step := Vector3(area_size.x / count_x, 0.0, area_size.z / count_z)
	var area_offset := -area_size / 2 + Vector3(area_step.x * 0.5, 0.0, area_step.z * 0.5)

	instance.multimesh.instance_count = count_x * count_z
	for z in range(count_z):
		for x in range(count_z):
			var index := x + z * count_x
			var xform := Transform3D()
			xform.origin = area_offset + Vector3(x * area_size.x / count_x, 0.0, z * area_size.z / count_z)
			xform.origin += area_step * Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))
			xform.basis = xform.basis.scaled(Vector3.ONE * randf_range(0.5, 0.8))
			xform.basis *= Basis.from_euler(Vector3(randf_range(-PI/16, PI/16), randf_range(-PI, PI), randf_range(-PI/16, PI/16)), EULER_ORDER_YXZ)
			instance.multimesh.set_instance_transform(index, xform)

