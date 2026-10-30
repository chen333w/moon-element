// 冻结契约：对外暴露的数据库视图。

///|
pub(all) struct ColumnInfo {
  name : String
  declared_type : String
  not_null : Bool
  primary_key : Bool
}

///|
pub(all) struct TableInfo {
  name : String
  sql : String
  root_page : Int32
  columns : Array[ColumnInfo]
  /// WITHOUT ROWID 表是索引 b-tree，没有 rowid。
  without_rowid : Bool
}

///|
pub(all) struct Row {
  rowid : Int64
  values : Array[@format.Value]
}
