/// 游戏状态机。
///
/// 状态流转（单向，除 resume 外不可回退）：
/// ```
///   ready ──tap──> playing ──hit──> dying ──落地──> gameOver ──restart──> ready
/// ```
///
/// - [ready]：待机。小鸟原地上下浮动，屏幕提示点击开始。
/// - [playing]：进行中。物理生效，管道滚动，碰撞检测开启。
/// - [dying]：已撞击。管道与地面停止滚动，小鸟进入自由落体（保留一段「摔落」演出），
///   此阶段仍受重力但不响应输入。独立成态是为了让死亡有一小段缓冲，
///   避免撞击瞬间直接弹结算面板导致的突兀感。
/// - [gameOver]：已落地。弹出结算面板，可重开。
enum GameState {
  ready,
  playing,
  dying,
  gameOver;

  /// 是否处于可以响应用户点击起飞的状态。
  bool get acceptsFlapInput => this == GameState.ready || this == GameState.playing;

  /// 是否处于世界仍在运动（管道滚动）的状态。
  bool get isWorldScrolling => this == GameState.ready || this == GameState.playing;
}
