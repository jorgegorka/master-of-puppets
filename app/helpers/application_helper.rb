module ApplicationHelper
  def polymorphic_actor_label(record, type_method: :actor_type, assoc: :actor)
    type = record.public_send(type_method)
    obj  = record.public_send(assoc)
    case type
    when "User"   then obj&.email_address || "Unknown user"
    when "Column" then obj&.name || "Unknown column"
    when "Run"    then "Run ##{obj&.id}"
    when nil      then "System"
    else type
    end
  end
end
