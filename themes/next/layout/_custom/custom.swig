{# 鼠标点击特效 #}
{% if theme.cursor_effect == "fireworks" %}
  <script async src="{{ config.root }}js/cursor/fireworks.js"></script>
{% elseif theme.cursor_effect == "explosion" %}
  <canvas class="fireworks" style="position: fixed;left: 0;top: 0;z-index: 1; pointer-events: none;" ></canvas>
  <script src="//cdn.bootcss.com/animejs/2.2.0/anime.min.js"></script>
  <script async src="{{ config.root }}js/cursor/explosion.min.js"></script>
{% elseif theme.cursor_effect == "love" %}
  <script async src="{{ config.root }}js/cursor/love.min.js"></script>
{% endif %}

{# 打字特效 #}
{% if theme.typing_effect %}
  <script src="{{ config.root }}js/activate-power-mode.min.js"></script>
  <script>
    POWERMODE.colorful = {{ theme.typing_effect.colorful }};
    POWERMODE.shake = {{ theme.typing_effect.shake }};
    document.body.addEventListener('input', POWERMODE);
  </script>
{% endif %}

{# Tidio 在线联系功能 #}
{% if theme.tidio.enable %}
<script src="//code.tidio.co/0yoj5e9wjgnfe9057ghmw0u0l7wqn3hk.js" async></script>
{% endif %}