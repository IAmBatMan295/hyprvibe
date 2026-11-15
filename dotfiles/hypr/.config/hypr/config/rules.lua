hl.window_rule({
	match = { class = "code" },
	opacity = "0.8 1.0 override",
})

-- Layer Rules for Blur & Animations
hl.layer_rule({ match = { namespace = "hyprvibe-bar" }, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "notifications" }, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "rofi" }, blur = true, ignore_alpha = 0.5 })
hl.layer_rule({ match = { namespace = "hyprvibe-keyboard-panel.*" }, no_anim = true })

hl.window_rule({
	match = { class = "^steam_app_.*$" },
	immediate = true,
	no_blur = true,
	no_shadow = true,
})
