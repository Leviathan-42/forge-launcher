<script lang="ts">
  import { icons, type IconName } from "$lib/icons";

  export let name: IconName;
  export let size = 16;
  export let label = "";
</script>

<span
  class="icon"
  aria-hidden={label ? undefined : "true"}
  aria-label={label || undefined}
  style={`width:${size}px;height:${size}px;`}
>
  {@html icons[name]}
</span>

<style>
  .icon {
    display: inline-flex;
    flex: 0 0 auto;
    align-items: center;
    justify-content: center;
    color: currentColor;
    line-height: 0;
  }

  .icon :global(svg) {
    display: block;
    width: 100%;
    height: 100%;
    stroke: currentColor;
  }
</style>
