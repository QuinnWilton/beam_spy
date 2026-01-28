// A simple Gleam test fixture for BeamSpy testing

pub fn hello() -> String {
  "Hello from Gleam!"
}

pub fn add(a: Int, b: Int) -> Int {
  a + b
}

pub fn greet(name: String) -> String {
  "Hello, " <> name <> "!"
}

pub type Person {
  Person(name: String, age: Int)
}

pub fn create_person(name: String, age: Int) -> Person {
  Person(name: name, age: age)
}

pub fn get_name(person: Person) -> String {
  person.name
}

pub fn map_list(list: List(a), f: fn(a) -> b) -> List(b) {
  case list {
    [] -> []
    [head, ..tail] -> [f(head), ..map_list(tail, f)]
  }
}

pub fn fold_list(list: List(a), acc: b, f: fn(b, a) -> b) -> b {
  case list {
    [] -> acc
    [head, ..tail] -> fold_list(tail, f(acc, head), f)
  }
}
