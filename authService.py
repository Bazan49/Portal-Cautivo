import json
import hashlib
class AuthService:
    def __init__(self, data = 'dataUsers.json'):
        self.user_data = data
        self._load_users()

    def _load_users(self):
        try:
            with open(self.user_data, 'r') as file:
                self.users = json.load(file).get('users', [])
        except FileNotFoundError:
            self.users = []

    def _add_user(self, username, email,  password):
        password_hash = self.__hash_password(password)
        new_user = {
            "username": username,
            "email": email,
            "password_hash": password_hash,
            "activo": True
        }
        self.users.append(new_user)
        with open(self.user_data, 'w') as file:
            json.dump({'users': self.users}, file, indent=4)
    
    def __hash_password(self, password):
        return hashlib.sha256(password.encode('utf-8')).hexdigest()

    def validate_user(self, username, password):
        hashed_password = self.__hash_password(password)
        for user in self.users:
            if user['username'] == username and user['password_hash'] == hashed_password and user.get('activo', False):
                return {'status': 'success', 'username': username}
        return {'status': 'failure', 'error_type': 'invalid'}
    
    def register_user(self, username, email, password):
        # Comprobar si el usuario ya existe
        for user in self.users:
            if user['username'] == username:
                return {'status': 'failure', 'error_type': 'exists'}
        self._add_user(username, email, password)
        return {'status': 'success', 'username': username}