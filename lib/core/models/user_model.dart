class UserModel {
  final int id;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final String? address;
  final String? photo;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.address,
    this.photo,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'] as int,
    name: json['name']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    role: json['role']?.toString() ?? '',
    phone: json['phone']?.toString(),
    address: json['address']?.toString(),
    photo: json['photo']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'phone': phone,
    'address': address,
    'photo': photo,
  };

  UserModel copyWith({String? photo}) => UserModel(
    id: id,
    name: name,
    email: email,
    role: role,
    phone: phone,
    address: address,
    photo: photo ?? this.photo,
  );
}
