/// A component library as OpenUI describes it (prompt.md §2). The JSON round trip arrives with task 1.3.
class LibrarySpec {
  LibrarySpec(this.json);

  factory LibrarySpec.fromJson(Map<String, Object?> json) => LibrarySpec(json);

  final Map<String, Object?> json;

  Map<String, Object?> toJson() => json;
}
