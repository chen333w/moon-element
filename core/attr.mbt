///|
/// 属性的值类型。
///
/// 对应「HTML 属性字符串 → MoonBit 值」的转换规则。布尔属性遵循 HTML 语义：
/// **属性存在即为 true**，与属性的字面内容无关（`<x-flag>` 与 `<x-flag="">` 都是 true），
/// 因此 `AttrBool` 的解析结果只取决于属性存在与否。
pub(all) enum AttrKind {
  AttrString
  AttrInt
  AttrDouble
  AttrBool
}

///|
/// 属性的值。
///
/// 整数用 `Int` 承载。解析侧把可接受的位数限制为 **最多 9 位十进制数字**：
/// `Int` 的宽度可能随后端而异，限制位数可以保证「不接受的值一律回退默认值」，
/// 而不是在某些后端上静默溢出、在另一些后端上正常——跨后端行为必须一致。
pub(all) enum AttrValue {
  VString(String)
  VInt(Int32)
  VDouble(Double)
  VBool(Bool)
} derive(Eq, @debug.Debug)

///|
/// `derive(Eq)` 生成的方法默认会被隐式提升为普通方法（已废弃行为），
/// 显式声明一次以保留 `==` 能力并消除该警告。
pub extend AttrValue with Eq::{equal, not_equal}

///|
/// 同上：显式声明 `Debug` 的方法，消除隐式提升的废弃警告。
pub extend AttrValue with @debug.Debug::{to_repr}

///|
/// 一个「可观察属性」的规格。
///
/// - `attr_name` 是 HTML 侧的名字，按惯例用 kebab-case（如 `max-count`）
/// - MoonBit 侧的名字（camelCase）由 `prop_name()` 推导，避免两处各写一遍而不一致
/// - `default` 是属性缺失**或值非法**时使用的值
pub struct AttrSpec {
  attr_name : String
  kind : AttrKind
  default : AttrValue
}

///|
pub fn AttrSpec::string(attr_name : String, default : String) -> AttrSpec {
  { attr_name, kind: AttrString, default: VString(default), }
}

///|
pub fn AttrSpec::int(attr_name : String, default : Int32) -> AttrSpec {
  { attr_name, kind: AttrInt, default: VInt(default), }
}

///|
pub fn AttrSpec::double(attr_name : String, default : Double) -> AttrSpec {
  { attr_name, kind: AttrDouble, default: VDouble(default), }
}

///|
pub fn AttrSpec::bool(attr_name : String, default : Bool) -> AttrSpec {
  { attr_name, kind: AttrBool, default: VBool(default), }
}

///|
/// MoonBit 侧的属性名：`max-count` → `maxCount`。
pub fn AttrSpec::prop_name(self : AttrSpec) -> String {
  kebab_to_camel(self.attr_name)
}

///|
/// 解析属性的原始值。
///
/// - `None`（属性不存在或已被移除）→ 默认值
/// - 字符串非法（例如 `AttrInt` 却给了 `"abc"`）→ **默认值**，与 HTML 的宽松语义一致
/// - `AttrBool`：`Some(_)` 一律为 true（存在即真）
pub fn AttrSpec::parse(self : AttrSpec, raw : String?) -> AttrValue {
  match raw {
    None => self.default
    Some(s) =>
      match self.kind {
        AttrString => VString(s)
        AttrInt =>
          match parse_int(s) {
            Some(v) => VInt(v)
            None => self.default
          }
        AttrDouble =>
          match parse_double(s) {
            Some(v) => VDouble(v)
            None => self.default
          }
        AttrBool => VBool(true)
      }
  }
}

///|
/// 值 → 属性字符串；返回 `None` 表示「应当移除该属性」。
///
/// 只有 `VBool(false)` 会返回 `None`：布尔属性的真假由「属性存在与否」承载，
/// 不能靠把字符串设成 `"false"` 来表达（那反而会被按存在即真解析成 true）。
pub fn AttrValue::to_attr(self : AttrValue) -> String? {
  match self {
    VString(s) => Some(s)
    VInt(v) => Some(v.to_string())
    VDouble(v) => Some(v.to_string())
    VBool(true) => Some("")
    VBool(false) => None
  }
}

///|
/// 由属性规格推导 `observedAttributes`：只有这里列出的属性名才会收到变更回调。
pub fn observed_attributes(specs : Array[AttrSpec]) -> Array[String] {
  let out : Array[String] = []
  for spec in specs {
    out.push(spec.attr_name)
  }
  out
}

///|
fn digit_value(c : Char) -> Int32? {
  let v = c.to_int() - '0'.to_int()
  if v >= 0 && v <= 9 {
    Some(v)
  } else {
    None
  }
}

///|
fn is_ascii_upper(c : Char) -> Bool {
  let v = c.to_int()
  v >= 'A'.to_int() && v <= 'Z'.to_int()
}

///|
fn ascii_to_upper(c : Char) -> Char {
  if is_ascii_upper(c) {
    c
  } else {
    let v = c.to_int()
    if v >= 'a'.to_int() && v <= 'z'.to_int() {
      match (v - 32).to_char() {
        Some(u) => u
        None => c
      }
    } else {
      c
    }
  }
}

///|
fn ascii_to_lower(c : Char) -> Char {
  let v = c.to_int()
  if v >= 'A'.to_int() && v <= 'Z'.to_int() {
    match (v + 32).to_char() {
      Some(l) => l
      None => c
    }
  } else {
    c
  }
}

///|
/// `max-count` → `maxCount`（ASCII kebab-case → camelCase）。
///
/// 连续短横线只起一次大写作用（`a--b` → `aB`）；结尾短横线被忽略（`a-` → `a`）；
/// 开头短横线会把首字母大写（`-a` → `A`）。
pub fn kebab_to_camel(name : String) -> String {
  let out : Array[Char] = []
  let n = name.char_length()
  let mut i : Int32 = 0
  let mut upper_next = false
  while i < n {
    match name.get_char(i) {
      Some(c) =>
        if c == '-' {
          upper_next = true
        } else if upper_next {
          out.push(ascii_to_upper(c))
          upper_next = false
        } else {
          out.push(c)
        }
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
/// `maxCount` → `max-count`（ASCII camelCase → kebab-case）。
///
/// 每个大写字母前插一个短横线，首字符除外（`MaxCount` → `max-count`）。
pub fn camel_to_kebab(name : String) -> String {
  let out : Array[Char] = []
  let n = name.char_length()
  let mut i : Int32 = 0
  while i < n {
    match name.get_char(i) {
      Some(c) =>
        if is_ascii_upper(c) {
          if i > 0 {
            out.push('-')
          }
          out.push(ascii_to_lower(c))
        } else {
          out.push(c)
        }
      None => ()
    }
    i = i + 1
  }
  String::from_iter(out.iter())
}

///|
/// 严格解析十进制整数。
///
/// 接受：可选 `+`/`-`，随后 1–9 位十进制数字。前导零允许（`007` → 7）。
/// 拒绝：空串、只有符号、空白、下划线、小数点、科学计数法、10 位及以上的数字
/// （位数上限是为了让跨后端行为一致，见 `AttrValue` 的说明）。
pub fn parse_int(s : String) -> Int32? {
  let n = s.char_length()
  if n == 0 {
    return None
  }
  let mut i : Int32 = 0
  let mut negative = false
  match s.get_char(0) {
    Some(c) =>
      if c == '-' {
        negative = true
        i = 1
      } else if c == '+' {
        i = 1
      }
    None => return None
  }
  if i >= n {
    return None
  }
  let mut acc : Int32 = 0
  let mut digits = 0
  while i < n {
    let ok = match s.get_char(i) {
      Some(c) =>
        match digit_value(c) {
          Some(d) => {
            acc = acc * 10 + d
            digits = digits + 1
            digits <= 9
          }
          None => false
        }
      None => false
    }
    if !ok {
      return None
    }
    i = i + 1
  }
  if negative {
    Some(-acc)
  } else {
    Some(acc)
  }
}

///|
/// 严格解析十进制小数。
///
/// 接受：可选 `+`/`-`，整数部分 0–9 位，可选 `.` 加 1–9 位小数；整数与小数部分
/// 加起来至少 1 位（所以 `.5` 与 `5` 合法，`.`、`5.` 非法）。
/// 拒绝：空白、科学计数法（`1e3`）、十六进制、多个小数点、小数超过 9 位。
///
/// 小数部分先按整数累加、最后只做一次除法，以减少累积误差。
pub fn parse_double(s : String) -> Double? {
  let n = s.char_length()
  if n == 0 {
    return None
  }
  let mut i : Int32 = 0
  let mut negative = false
  match s.get_char(0) {
    Some(c) =>
      if c == '-' {
        negative = true
        i = 1
      } else if c == '+' {
        i = 1
      }
    None => return None
  }
  let mut int_part : Int32 = 0
  let mut int_digits = 0
  let mut frac_part : Int32 = 0
  let mut frac_digits = 0
  let mut seen_dot = false
  while i < n {
    match s.get_char(i) {
      Some(c) =>
        if c == '.' {
          if seen_dot {
            return None
          }
          seen_dot = true
        } else {
          match digit_value(c) {
            Some(d) =>
              if seen_dot {
                frac_digits = frac_digits + 1
                if frac_digits > 9 {
                  return None
                }
                frac_part = frac_part * 10 + d
              } else {
                int_digits = int_digits + 1
                if int_digits > 9 {
                  return None
                }
                int_part = int_part * 10 + d
              }
            None => return None
          }
        }
      None => return None
    }
    i = i + 1
  }
  if int_digits + frac_digits == 0 {
    return None
  }
  if seen_dot && frac_digits == 0 {
    return None
  }
  let mut value = Double::from_int(int_part)
  if frac_digits > 0 {
    let mut scale = 1.0
    let mut k = 0
    while k < frac_digits {
      scale = scale * 10.0
      k = k + 1
    }
    value = value + Double::from_int(frac_part) / scale
  }
  if negative {
    Some(-value)
  } else {
    Some(value)
  }
}
