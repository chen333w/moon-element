// 冻结契约：格式层的值类型。上层（btree/db/CLI）都只依赖这里。

///|
/// SQLite 的五个存储类。
pub(all) enum Value {
  Null
  Int(Int64)
  Real(Double)
  Text(String)
  Blob(Bytes)
}

///|
pub fn Value::type_name(self : Value) -> String {
  match self {
    Null => "null"
    Int(_) => "integer"
    Real(_) => "real"
    Text(_) => "text"
    Blob(_) => "blob"
  }
}
