class FoodDrugInteraction {
  final String foodToTake;
  final String description;
  final String url;
  final String url1;
  final String url2;
  final String url3;
  final String searchKey;
  final String id;
  final String interactingWith;
  final String foodToAvoid;
  final String drugName;
  final String timeToTake;

  FoodDrugInteraction({
    required this.foodToTake,
    required this.description,
    required this.url,
    required this.url1,
    required this.url2,
    required this.url3,
    required this.searchKey,
    required this.id,
    required this.interactingWith,
    required this.foodToAvoid,
    required this.drugName,
    required this.timeToTake,
  });

  factory FoodDrugInteraction.fromJson(Map<String, dynamic> json) {
    return FoodDrugInteraction(
      foodToTake: json['foodToTake'] ?? '',
      description: json['description'] ?? '',
      url: json['url'] ?? '',
      url1: json['url1'] ?? '',
      url2: json['url2'] ?? '',
      url3: json['url3'] ?? '',
      searchKey: json['searchKey'] ?? '',
      id: json['id']?.toString() ?? '',
      interactingWith: json['interactingWith'] ?? '',
      foodToAvoid: json['foodToAvoid'] ?? '',
      drugName: json['drugName'] ?? '',
      timeToTake: json['timeToTake'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'foodToTake': foodToTake,
      'description': description,
      'url': url,
      'url1': url1,
      'url2': url2,
      'url3': url3,
      'searchKey': searchKey,
      'id': id,
      'interactingWith': interactingWith,
      'foodToAvoid': foodToAvoid,
      'drugName': drugName,
      'timeToTake': timeToTake,
    };
  }
}
