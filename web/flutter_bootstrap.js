{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    const runner = await engineInitializer.initializeEngine();
    const { repairCanvasKitPathFillType } = await import(
      new URL('canvaskit_path_compat.mjs', document.baseURI).href);
    // 按实际返回值探测，只回收旧实现的独立副本，不删除原路径或同源句柄。
    window.__easyCreatePathFillFix = repairCanvasKitPathFillType(window.flutterCanvasKit);
    await runner.runApp();
  },
});
