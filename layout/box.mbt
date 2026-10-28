// 布局结果的只读查询：盒子计数、按前序下标回查几何。

///|
// 盒子总数（含文本盒）。
pub fn LayoutBox::count(self : LayoutBox) -> Int32 {
  match self {
    LayoutBox::Box(b) => {
      let mut n = 1
      for c in b.children {
        n = n + c.count()
      }
      n
    }
    LayoutBox::Text(_) => 1
  }
}

///|
// 按输入节点的前序下标查边框盒；display:none 的节点没有盒子，返回 None。
pub fn LayoutBox::find(self : LayoutBox, node : Int32) -> Rect? {
  match self {
    LayoutBox::Box(b) =>
      if b.node == node {
        Some(b.rect)
      } else {
        let mut hit : Rect? = None
        for c in b.children {
          match hit {
            Some(_) => ()
            None =>
              match c.find(node) {
                Some(r) => hit = Some(r)
                None => ()
              }
          }
        }
        hit
      }
    LayoutBox::Text(t) => if t.node == node { Some(t.rect) } else { None }
  }
}
