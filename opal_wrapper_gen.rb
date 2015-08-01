require 'json'
require 'fileutils'

class Yuidoc
  js = {}
  data = {}
  def initialize(json)
    @js = JSON.parse(json.read())
    self.parse_data()
  end
  
  def write()
    CodeGen::new(@data).finish()
  end
  
  protected
  def parse_data
    tmpa = []; tmp = {}
    for k, v in @js["modules"]
      tmp["name"] = self.normalize_object_name(k)
      tmp["native_name"] = k
      tmp["classes"] = self.get_classes(k)
      tmp["description"] = self.render_description(v["description"])
      tmpa.push(tmp); tmp = {}
    end
    @data = tmpa
  end
  
  def get_classes(module_name)
    cls = {}; cls2 = []
    for cls_name, _ in @js["modules"][module_name]["classes"]
  
      cname = self.normalize_object_name(cls_name)
      if ["instanceOf", "Class", "namespace", "Interface", "$cache", "forName", "ready"].include?(cname) then next end 
      
      descr = self.test_nil(@js["classes"][cls_name]["description"], nil)
      params = self.test_nil(@js["classes"][cls_name]["params"], nil)
      
      cls["native_name"] = cls_name
      cls["description"] = self.render_description(descr, params)
      cls["name"] = cname
      cls["attributes"] = self.get_attributes(cls_name, module_name)
      cls["methods"] = self.get_methods(cls_name, module_name)
      cls["params"] = self.test_nil(@js["classes"][cls_name]["params"], nil)
      cls2.push(cls); cls = {}
    end
    cls2
  end
  
  def get_attributes(class_name, module_name)
  attr = []; tmp = {}; filtered = {}
  filtered = self.filter_classitems(Type::ATTRIBUTE, class_name, module_name)
  
    for f in filtered[module_name][class_name]
      tmp["description"] = self.render_description(f["description"])
      tmp["name"] = self.snake_case(f["name"])
      tmp["native_name"] = f["name"]
      attr.push(tmp); tmp = {}
    end
    attr
  end
  
  def get_methods(class_name, module_name)
    mtd = []; tmp = {}; filtered = {}
    filtered = self.filter_classitems(Type::METHOD, class_name, module_name)
  
    for f in filtered[module_name][class_name]
      tmp["description"] = self.render_description(f["description"], f["params"])
      tmp["name"] = self.snake_case(f["name"])
      tmp["native_name"] = f["name"]
      tmp["access"] = f["access"]
      tmp["params"] = f["params"]
      mtd.push(tmp); tmp = {}
    end

    mtd
  end
      
  def to_path(str)
    str.gsub(".", File::SEPARATOR)
  end
  
  def render_description(str, params = nil)
    if str.nil? then return "" end
    retstr = ""; par = "# \n# @params:\n"
    str << "\n"
      str.each_line do |s| retstr << s.insert(0, "# ") end
    if !params.nil? then
      tmp = ""
      for para in params
        tmp << para["description"].gsub("\n", "\n# ")
        par << "#    @#{para["name"]} (#{para["type"]}) #{tmp}\n"
      end
      retstr << par
    end
    retstr
  end
  
  def snake_case(str)
    tmp = ""
    str.each_char do |d|  
      if 'A' <= d && d <= 'Z'
        tmp << "_" << d.downcase
      else
        tmp << d
      end
    end
    tmp
  end
  
  def normalize_object_name(name)
    name.sub("()", "").split(".")[-1]
  end
  
  def test_nil(var, defval = "")
    if var.nil?
      return defval
    else
      return var
    end
  end
  
  # Filter "classitems" JSON data
  def filter_classitems(type, class_name, module_name)
    tmp = []; tmp2 = {}; fclsitems = {
      module_name => {
        class_name => []
      }
    }
    for cls in @js["classitems"] do      
      if cls["itemtype"] == type and 
         cls["module"] == module_name and 
         cls["class"] == class_name and
         cls["access"] != "private" then
        
        accs = if cls["access"].nil? then "public" else cls["access"] end
          
        tmp2["description"] = self.test_nil(cls["description"])
        tmp2["name"] = cls["name"]
        tmp2["params"] = self.test_nil(cls["params"], nil)
        tmp2["access"] = if accs == "protected" then 1 else 0 end
      else
        next
      end
      tmp.push(tmp2); tmp2 = {}
    end
    fclsitems[module_name][class_name] = tmp
    fclsitems
  end
end  


class Type
  METHOD = "method"
  ATTRIBUTE = "attribute"
  EVENT = "event"
end


class CodeGen
  hash = {}
 
  def initialize(hash)
    @hash = hash
  end
  
  protected
  def module_gen(name, description)
    tmp = description
    tmp << "module #{name}\n$classes$\nend\n\n"
    tmp
  end
  
  def method_gen(name, args, native, access, description)
    tmp = self.insert_each_line(description, "\t\t")
    tmp << "\t\t"
    tmp << "protected " if access == 1
    tmp << "def #{name}(#{self.params_join(args)})\n\t\t\t"
    tmp << "utils::native_method('#{native}')\n\t\tend\n\n"

    tmp
  end

  def class_gen(name, args, inh, description)
    tmp = self.insert_each_line(description)
    tmp << 
"    class #{name}
$attributes$
        def initialize(#{self.params_join(args)})
                utils::native_class('#{name}', '#{inh}')
        end

$methods$
    end
"   
    tmp
  end
  
  def attribute_gen(name, description)
    tmp = self.insert_each_line(description, "\t\t")
    tmp << "\t\t#{name}\n"
    tmp
  end
  
  def insert_each_line(str, ins = "\t")
    tmp = ""; str.each_line do |s|
      tmp << s.insert(0, ins)
    end
    tmp
  end
  
  def params_join(hash)
    ar = []; return "" if hash.nil?
    for a in hash
      ar << a["name"]
    end
    return ar.join(", ")
  end
  
  public
  def finish()
    tmp, tmp2, tmp3, tmp4 = "", "", "", ""
    for v in @hash
      tmp << self.module_gen(v["name"], v["description"])
      for v1 in v["classes"]
        tmp2 << self.class_gen(v1["name"], v1["params"], "", v1["description"])
        for v3 in v1["attributes"]
          tmp4 << self.attribute_gen(v3["name"], v3["description"])
        end
        for v2 in v1["methods"]
          tmp3 << self.method_gen(v2["name"], v2["params"], v2["native_name"], v2["access"], v2["description"])
        end
        tmp2.sub!("$attributes$", tmp4) ; tmp4 = "" 
        tmp2.sub!("$methods$", tmp3) ; tmp3 = "" 
      end
      tmp.sub!("$classes$", tmp2) ; tmp2 = ""
    
      path = v["native_name"].gsub(".", "/")
      directory_name = "opal_wrapper_gen_dir" + "/" + path + ".rb"
      FileUtils.mkdir_p(File.dirname(directory_name))
      File.open(directory_name, 'w') do |file| 
       file.write("require 'opw_utils'\n\n" + tmp)
      end
      tmp = ""
    end
  end
end


if ARGV[0].nil?
  p "ruby opal_wrapper_gen.rb [file_name]"
else
  Yuidoc::new(open(ARGV[0])).write()
  p "DONE!!"
end
