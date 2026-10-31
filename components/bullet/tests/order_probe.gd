extends SceneTree
## Decisive ordering probe: does node _physics_process run BEFORE or AFTER
## PhysicsServer2D integrates the bodies this tick?
## - Script-before-step: first print y = 0.0000, then 0.1389, 0.5556
## - Step-before-script: first print y = 0.1389, then 0.5556, 1.2500
## (gravity 500, v0 = 0, dt = 1/60 => y after N steps = g*dt^2*N*(N+1)/2)

func _initialize():
	var host := Node.new()
	host.set_script(preload("res://components/bullet/tests/order_host.gd"))
	root.add_child(host)
	var body := RigidBody2D.new()
	body.name = "Body"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 4.0
	shape.shape = circle
	body.add_child(shape)
	body.gravity_scale = 1.0
	body.global_position = Vector2(0, 0)
	host.add_child(body)
	# Safety: never hang the headless run.
	var guard := Timer.new()
	guard.wait_time = 5.0
	guard.one_shot = true
	guard.timeout.connect(quit)
	root.add_child(guard)
	guard.start()
