// 動きを減らす設定のときは自動再生せず、再生ボタンを出す
if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  document.querySelectorAll("video[autoplay]").forEach((video) => {
    video.removeAttribute("autoplay");
    video.pause();
    video.controls = true;
  });
}
