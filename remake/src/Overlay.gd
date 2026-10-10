extends Control
## Small helper: a Control whose drawing is delegated to a Callable, so several
## layers can be interleaved with other children in the scene tree.

var draw_cb: Callable

func _draw() -> void:
	if draw_cb.is_valid():
		draw_cb.call(self)
